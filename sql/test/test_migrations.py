"""Essaie les migrations sur une base locale jetable (jamais Supabase).
Lancer : python3 sql/test/test_migrations.py"""
import os, sys, json; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import *
ok = fail = 0
def t(name, fn):
    global ok, fail
    try: r = fn(); print("  OK  ", name, "" if r is None else r); ok += 1
    except Exception as e: print("  ECHEC", name, "->", str(e).strip().splitlines()[0]); fail += 1
def must_fail(fn, word):
    try: fn()
    except Exception as e:
        if word in str(e): return "refusé: " + word
        raise
    raise AssertionError("aurait dû être refusé (" + word + ")")

srv, d = start(); c = connect(srv)
def sql(q, a=None):
    with c.cursor() as cur:
        cur.execute(q, a)
        try: return cur.fetchall()
        except psycopg2.ProgrammingError: return None
try:
    sql(STUB)
    for f in ["schema_v1_v4.sql", "schema_v5.sql"]: run_file(c, f"{HIST}/{f}")
    run_file(c, V6A); sql(SEED)
    run_file(c, f"{REPO}/schema_v6_v7.sql"); run_file(c, f"{REPO}/schema_v8_v9.sql")
    sql("update public.app_settings set value = 'false' where key = 'maintenance'") if sql("select to_regclass('public.app_settings')")[0][0] else None
    print("app_settings:", sql("select * from public.app_settings"))

    print("== v6 : profils, badges exclusifs, blocage")
    t("badge fondateur pour tintintest", lambda: sql(f"select badge_code from user_badges where user_id='{U1}' and badge_code in ('founder','beta_founder')"))
    t("badge bêta fondatrice pour joh et zed", lambda: sql("select count(*) from user_badges where badge_code='beta_founder'"))
    t("me() contient avatar", lambda: as_user(c, U1, "select me()->>'avatar', me()->>'bc'"))
    t("set_avatar av_05", lambda: as_user(c, U1, "select set_avatar('av_05')"))
    t("set_avatar inconnu refusé", lambda: must_fail(lambda: as_user(c, U1, "select set_avatar('zz')"), "unknown avatar"))
    t("set_featured_badge founder", lambda: as_user(c, U1, "select set_featured_badge('founder')"))
    t("badge non possédé refusé", lambda: must_fail(lambda: as_user(c, U2, "select set_featured_badge('founder')"), "not owned"))
    t("écriture directe sur profiles refusée", lambda: must_fail(lambda: as_user(c, U1, "update profiles set pseudo='hack' where id=auth.uid()"), "permission denied"))
    t("écriture directe sur player_stats refusée", lambda: must_fail(lambda: as_user(c, U1, "update player_stats set bc=99999 where user_id=auth.uid()"), "permission denied"))
    t("add_bc interne non appelable", lambda: must_fail(lambda: as_user(c, U1, f"select add_bc('{U1}', 1000, 'hack')"), "permission denied"))
    t("send_gift supprimée", lambda: must_fail(lambda: as_user(c, U1, "select send_gift('joh', 10)"), "does not exist"))
    t("my_friends (5 colonnes)", lambda: as_user(c, U1, "select * from my_friends()"))
    t("public_profile ami = vue complète", lambda: list(as_user(c, U1, "select public_profile('joh')")[0][0].keys()))
    t("public_profile non-ami = pas de stats", lambda: as_user(c, U3, "select public_profile('tintintest')->'games'"))
    t("message entre amis", lambda: as_user(c, U1, "select send_message('joh','coucou')"))
    t("joh bloque tintintest", lambda: as_user(c, U2, "select block_user('tintintest')"))
    t("amitié supprimée par le blocage", lambda: sql("select count(*) from friendships"))
    t("message bloqué refusé", lambda: must_fail(lambda: as_user(c, U1, "select send_message('joh','re')"), "blocked"))
    t("fiche d'un joueur qui m'a bloqué = inconnu", lambda: must_fail(lambda: as_user(c, U1, "select public_profile('joh')"), "unknown player"))
    t("my_blocks", lambda: as_user(c, U2, "select * from my_blocks()"))
    t("débloquer", lambda: as_user(c, U2, "select unblock_user('tintintest')"))
    t("arena_check joueur bêta", lambda: as_user(c, U2, "select arena_check()"))
    t("arena_check visiteur refusé", lambda: must_fail(lambda: as_user(c, None, "select arena_check()"), "permission denied"))
    t("badge exclusif indélébile", lambda: must_fail(lambda: sql(f"delete from user_badges where user_id='{U2}' and badge_code='beta_founder'"), "permanent"))

    print("== v7 : signalement de bugs")
    t("submit_bug_report", lambda: as_user(c, U2, "select submit_bug_report('game','Le serpent traverse le mur', 'snake','snake','test-v7', '{\"ua\":\"x\"}'::jsonb, null)"))
    t("description trop courte refusée", lambda: must_fail(lambda: as_user(c, U2, "select submit_bug_report('game','court')"), "invalid description"))
    t("staff_bug_list pour fondateur", lambda: len(as_user(c, U1, "select * from staff_bug_list(null)")))
    t("staff_bug_list refusé à un joueur", lambda: must_fail(lambda: as_user(c, U2, "select * from staff_bug_list(null)"), "forbidden"))
    t("staff_export : tables", lambda: sorted(as_user(c, U1, "select staff_export()->'integrity'")[0][0].keys()))
    t("leaderboard accessible aux visiteurs", lambda: as_user(c, None, "select count(*) from leaderboard('snake','FR',10)"))

    print("== v8 : BoyBlocks vérifié côté base")
    run_id, seed = None, None
    r = as_user(c, U2, "select boyblocks_start()")[0][0]; print("  run", r)
    seed = r["seed"]; run_id = r["run_id"]
    # partie jouée automatiquement : à chaque coup, la 1re pièce posable à la 1re place libre
    shapes = {row[0]: row[1:] for row in sql("select id, n, cells from bb_shapes")}
    moves = []
    for _ in range(400):
        ok_, err, at, score, nm, lines, best, over = sql("select * from bb_replay(%s, %s::jsonb)", (seed, json.dumps(moves)))[0]
        if over: break
        # reconstruire l'état : pièces restantes du lot courant
        found = False
        for slot in range(3):
            for rr in range(8):
                for cc in range(8):
                    cand = moves + [[slot, rr, cc]]
                    if sql("select ok from bb_replay(%s, %s::jsonb)", (seed, json.dumps(cand)))[0][0]:
                        moves = cand; found = True; break
                if found: break
            if found: break
        if not found: break
    final = sql("select * from bb_replay(%s, %s::jsonb)", (seed, json.dumps(moves)))[0]
    print("  partie simulée : coups", final[4], "score", final[3], "lignes", final[5], "fin", final[7])
    t("finir trop vite refusé", lambda: must_fail(lambda: as_user(c, U2, "select boyblocks_finish(%s, %s::jsonb)", (run_id, json.dumps(moves))), "invalid run"))
    sql("update boyblocks_runs set started_at = now() - interval '10 minutes' where id = %s", (run_id,))
    t("coup impossible refusé", lambda: must_fail(lambda: as_user(c, U2, "select boyblocks_finish(%s, %s::jsonb)", (run_id, json.dumps(moves + [[0, 9, 9]]))), "invalid run"))
    t("boyblocks_finish (score recalculé)", lambda: as_user(c, U2, "select boyblocks_finish(%s, %s::jsonb)", (run_id, json.dumps(moves)))[0][0])
    t("partie déjà terminée refusée", lambda: must_fail(lambda: as_user(c, U2, "select boyblocks_finish(%s, %s::jsonb)", (run_id, json.dumps(moves))), "invalid run"))
    t("partie d'un autre joueur refusée", lambda: must_fail(lambda: as_user(c, U3, "select boyblocks_finish(%s, '[]'::jsonb)", (run_id,)), "invalid run"))
    t("submit_score('boyblocks') refusé (score non vérifié)", lambda: must_fail(lambda: as_user(c, U2, "select submit_score('boyblocks', 99999)"), "unknown game"))
    t("bb_replay non appelable par un joueur", lambda: must_fail(lambda: as_user(c, U2, "select * from bb_replay(1, '[]'::jsonb)"), "permission denied"))
    t("tables BoyBlocks illisibles", lambda: must_fail(lambda: as_user(c, U2, "select * from boyblocks_runs"), "permission denied"))
    t("mission bb_1500 visible", lambda: [m for m in as_user(c, U2, "select code, progress from my_missions()") if m[0]=='bb_1500'])
    t("classement boyblocks", lambda: as_user(c, U2, "select * from leaderboard('boyblocks', null, 5)"))

    print("== v9 : badges à paliers")
    t("sync_tiers tintintest", lambda: as_user(c, U1, "select sync_tiers()")[0][0])
    t("sync_tiers 2e fois = rien de neuf", lambda: as_user(c, U1, "select sync_tiers()")[0][0])
    t("my_tiers", lambda: [(g['game'], g['tier']) for g in as_user(c, U1, "select my_tiers()")[0][0]['games']])
    t("set_favorites", lambda: as_user(c, U1, "select set_favorites(array['blocks:0','space:0'])"))
    t("favori non débloqué refusé", lambda: must_fail(lambda: as_user(c, U1, "select set_favorites(array['snake:5'])"), "not unlocked"))
    t("4 favoris refusé", lambda: must_fail(lambda: as_user(c, U1, "select set_favorites(array['a:0','b:0','c:0','d:0'])"), "too many"))
    t("public_tiers ami", lambda: as_user(c, U2, "select public_tiers('tintintest')")[0][0])
    t("public_tiers non-ami = vide", lambda: as_user(c, U3, "select public_tiers('tintintest')")[0][0])

    print("== suppression de compte (avec badge exclusif)")
    t("delete_my_account de zed_test", lambda: as_user(c, U3, "select delete_my_account()"))
    t("zed_test et ses badges supprimés", lambda: sql(f"select (select count(*) from auth.users where id='{U3}'), (select count(*) from user_badges where user_id='{U3}')"))

    print("== ordre de relance : v6+v7 relancée APRÈS v8+v9")
    run_file(c, f"{REPO}/schema_v6_v7.sql")
    t("boyblocks_start encore appelable", lambda: as_user(c, U2, "select boyblocks_start() ? 'seed'"))
    t("my_tiers encore appelable", lambda: as_user(c, U2, "select my_tiers() is not null"))
finally:
    c.close(); srv.cleanup(); shutil.rmtree(d, ignore_errors=True)
print(f"\n{ok} OK, {fail} échec(s)"); sys.exit(1 if fail else 0)

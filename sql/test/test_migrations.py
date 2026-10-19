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
def play(uid, game, value, ago=600):
    """Envoie un score comme le site depuis la v22 : ticket de partie puis submit_score_v2 (partie commencée il y a `ago` s)."""
    rid = as_user(c, uid, "select game_start(%s)", (game,))[0][0]
    sql("update game_runs set started_at = now() - make_interval(secs => %s) where id = %s", (ago, rid))
    sql("update scores set created_at = now() - interval '1 minute' where user_id = %s", (uid,))
    return as_user(c, uid, "select submit_score_v2(%s, %s, %s)", (game, value, rid))[0][0]
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
    old_run = as_user(c, U2, "select boyblocks_start()")[0][0]   # partie commencée AVANT la v10
    run_file(c, f"{REPO}/schema_v10_boyblocks_regles2.sql")
    run_file(c, f"{REPO}/schema_v11_economie_reglages.sql"); run_file(c, f"{REPO}/schema_v11_economie_reglages.sql")
    run_file(c, f"{REPO}/schema_v12_monetisation.sql"); run_file(c, f"{REPO}/schema_v12_monetisation.sql")
    run_file(c, f"{REPO}/schema_v13_marketing.sql"); run_file(c, f"{REPO}/schema_v13_marketing.sql")
    run_file(c, f"{REPO}/schema_v14_boyblocks_9x9.sql"); run_file(c, f"{REPO}/schema_v14_boyblocks_9x9.sql")
    run_file(c, f"{REPO}/schema_v15_questionnaire.sql"); run_file(c, f"{REPO}/schema_v15_questionnaire.sql")
    badges_avant = sql("select count(*) from user_badges")[0][0]
    run_file(c, f"{REPO}/schema_v16_espace_beta.sql"); run_file(c, f"{REPO}/schema_v16_espace_beta.sql")
    badges_apres = sql("select count(*) from user_badges")[0][0]
    run_file(c, f"{REPO}/schema_v17_plafond_space.sql"); run_file(c, f"{REPO}/schema_v17_plafond_space.sql")
    run_file(c, f"{REPO}/schema_v18_invitations.sql"); run_file(c, f"{REPO}/schema_v18_invitations.sql")
    run_file(c, f"{REPO}/schema_v19_liste_joueurs.sql"); run_file(c, f"{REPO}/schema_v19_liste_joueurs.sql")
    run_file(c, f"{REPO}/schema_v20_fiche_joueur.sql"); run_file(c, f"{REPO}/schema_v20_fiche_joueur.sql")
    run_file(c, f"{REPO}/schema_v21_stockage_marketing.sql"); run_file(c, f"{REPO}/schema_v21_stockage_marketing.sql")
    run_file(c, f"{REPO}/schema_v22_tickets_partie.sql"); run_file(c, f"{REPO}/schema_v22_tickets_partie.sql")
    run_file(c, f"{REPO}/schema_v6_v7.sql")   # la liste blanche relancée garde les fonctions du questionnaire
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
    t("submit_score('boyblocks') refusé (score non vérifié)", lambda: must_fail(lambda: as_user(c, U2, "select submit_score('boyblocks', 99999)"), "permission denied"))   # v22 : plus aucun envoi direct
    t("bb_replay non appelable par un joueur", lambda: must_fail(lambda: as_user(c, U2, "select * from bb_replay(1, '[]'::jsonb)"), "permission denied"))
    t("tables BoyBlocks illisibles", lambda: must_fail(lambda: as_user(c, U2, "select * from boyblocks_runs"), "permission denied"))
    t("mission bb_1500 visible", lambda: [m for m in as_user(c, U2, "select code, progress from my_missions()") if m[0]=='bb_1500'])
    t("classement boyblocks", lambda: as_user(c, U2, "select * from leaderboard('boyblocks', null, 5)"))

    print("== v10 : BoyBlocks règles 2 (tirage stratégique)")
    def playout(seed, rules, limit=400):
        mv = []
        for _ in range(limit):
            if sql("select over from bb_replay2(%s, %s::jsonb, true, %s)", (seed, json.dumps(mv), rules))[0][0]: break
            nxt = None
            for slot in range(3):
                for rr in range(8):
                    for cc in range(8):
                        if sql("select ok from bb_replay2(%s, %s::jsonb, true, %s)", (seed, json.dumps(mv + [[slot, rr, cc]]), rules))[0][0]:
                            nxt = [slot, rr, cc]; break
                    if nxt: break
                if nxt: break
            if not nxt: break
            mv.append(nxt)
        return mv
    r2 = as_user(c, U2, "select boyblocks_start_v2()")[0][0]
    t("boyblocks_start_v2 donne des parties règles 2", lambda: r2["rules"])
    mv2 = playout(r2["seed"], 2, 60)
    sql("update boyblocks_runs set started_at = now() - interval '10 minutes' where id in (%s, %s)", (r2["run_id"], old_run["run_id"]))
    t("fin de partie règles 2 acceptée", lambda: {k: v for k, v in as_user(c, U2, "select boyblocks_finish(%s, %s::jsonb)", (r2["run_id"], json.dumps(mv2)))[0][0].items() if k in ("score", "moves", "rules")})
    mv1 = playout(old_run["seed"], 1, 30)
    t("partie commencée avant la v10 : vérifiée avec l'ancien tirage", lambda: {k: v for k, v in as_user(c, U2, "select boyblocks_finish(%s, %s::jsonb)", (old_run["run_id"], json.dumps(mv1)))[0][0].items() if k in ("score", "moves", "rules")})
    r2b = as_user(c, U2, "select boyblocks_start_v2()")[0][0]
    mv_r1 = playout(r2b["seed"], 1, 40)        # coups joués avec l'ancien tirage sur une partie règles 2
    same = sql("select ok from bb_replay2(%s, %s::jsonb, true, 2)", (r2b["seed"], json.dumps(mv_r1)))[0][0]
    sql("update boyblocks_runs set started_at = now() - interval '10 minutes' where id = %s", (r2b["run_id"],))
    if same: print("  (sauté : par hasard les deux tirages coïncident sur cette graine)")
    else: t("coups « règles 1 » sur une partie règles 2 refusés", lambda: must_fail(lambda: as_user(c, U2, "select boyblocks_finish(%s, %s::jsonb)", (r2b["run_id"], json.dumps(mv_r1))), "invalid run"))
    t("bb_replay2 et bb_deal2 non appelables par un joueur", lambda: must_fail(lambda: as_user(c, U2, "select * from bb_replay2(1, '[]'::jsonb, true, 2)"), "permission denied"))
    import time, subprocess, shutil as _sh
    node = _sh.which("node") or os.path.expanduser("~/.local/node/bin/node")
    if os.path.exists(node):
        js = """import * as BB from '%s';
const g=BB.newGame(424242,{ensureFit:true,rules:2});
function bot(){let b=null,bs=-1e9;for(let s=0;s<3;s++){if(!g.pieces[s])continue;const sh=BB.PIECES[g.pieces[s].p];for(let r=0;r<=8-sh.h;r++)for(let c=0;c<=8-sh.w;c++){if(!BB.fits(g.grid,sh,r,c))continue;const cp=JSON.parse(JSON.stringify(g));const x=BB.place(cp,s,r,c);const sc=x.gain*3+cp.grid.filter(v=>!v).length+(x.over?-500:0);if(sc>bs){bs=sc;b=[s,r,c];}}}return b;}
while(!g.over&&g.moves<1500){const m=bot();if(!m)break;BB.place(g,m[0],m[1],m[2]);}
console.log(JSON.stringify({moves:g.log,score:g.score}));""" % os.path.join(os.path.dirname(REPO), "shared", "boyblocks-engine.js")
        long = json.loads(subprocess.check_output([node, "--input-type=module", "-e", js], text=True))
        t0 = time.time(); res = sql("select ok, score from bb_replay2(424242, %s::jsonb, true, 2)", (json.dumps(long["moves"]),))[0]; dt = time.time() - t0
        t(f"longue partie ({len(long['moves'])} coups) vérifiée en {dt:.2f} s, score identique", lambda: (res if res == (True, long["score"]) else (_ for _ in ()).throw(Exception(f"écart {res} != {long['score']}"))) and dt < 4 or (_ for _ in ()).throw(Exception(f"trop lent : {dt:.2f} s")))

    print("== v11 : réglages de l'économie (montants inchangés)")
    t("bonus de connexion lisible par le site", lambda: as_user(c, U1, "select economy_public()")[0][0])
    t("réglages illisibles en direct par un joueur", lambda: must_fail(lambda: as_user(c, U2, "select * from economy_settings"), "permission denied"))
    t("staff_economy refusé à un joueur", lambda: must_fail(lambda: as_user(c, U2, "select staff_economy()"), "forbidden"))
    t("staff_economy pour le fondateur", lambda: sorted(as_user(c, U1, "select staff_economy()")[0][0]["settings"].keys()))
    t("valeur hors bornes refusée", lambda: must_fail(lambda: as_user(c, U1, "select staff_economy_set('game_bc_daily_cap', '99999'::jsonb)"), "invalid value"))
    t("bonus de connexion à 7 valeurs exigé", lambda: must_fail(lambda: as_user(c, U1, "select staff_economy_set('daily_streak', '[1,2,3]'::jsonb)"), "invalid value"))
    def cap_applies():
        as_user(c, U1, "select staff_economy_set('game_bc_daily_cap', '2'::jsonb)")
        sql("update scores set created_at = now() - interval '1 minute'")
        r = play(U2, "space", 6000)["bc"]
        as_user(c, U1, "select staff_economy_set('game_bc_daily_cap', '150'::jsonb)")
        return r
    t("plafond modifié appliqué aux parties (2 BC max)", lambda: cap_applies() <= 2 or (_ for _ in ()).throw(Exception("plafond non appliqué")))
    t("changement de prix journalisé, objets achetés conservés", lambda: (as_user(c, U1, "select staff_set_price('title_rookie', 120)"), as_user(c, U1, "select staff_economy()")[0][0]["log"][0]["what"])[1])
    t("récompense de mission modifiable", lambda: (as_user(c, U1, "select staff_set_mission_reward('play_3', 12, 20)"), sql("select reward_bc from missions where code = 'play_3'")[0][0])[1])

    print("== v12 : monétisation (préparation, rien de réel)")
    t("réglages lisibles par un visiteur, tout désactivé", lambda: {k: v["enabled"] for k, v in as_user(c, None, "select monetization_public()")[0][0].items()})
    t("continuation refusée tant que désactivée", lambda: must_fail(lambda: as_user(c, U2, "select rewarded_continue('snake')"), "rewarded disabled"))
    t("jeu non compatible refusé dans les réglages", lambda: must_fail(lambda: as_user(c, U1, """select staff_monetization_set('rewarded', '{"enabled": true, "continue_max": 1, "daily_max": 2, "games": ["blocks"], "bc_per_continue": 0}'::jsonb)"""), "invalid game"))
    t("plus de 2 continuations refusé", lambda: must_fail(lambda: as_user(c, U1, """select staff_monetization_set('rewarded', '{"enabled": true, "continue_max": 3, "daily_max": 2, "games": ["snake"], "bc_per_continue": 0}'::jsonb)"""), "invalid value"))
    t("réglage refusé à un joueur", lambda: must_fail(lambda: as_user(c, U2, """select staff_monetization_set('ads', '{"enabled": true, "provider": "test", "slots": {}}'::jsonb)"""), "forbidden"))
    as_user(c, U1, """select staff_monetization_set('rewarded', '{"enabled": true, "continue_max": 1, "daily_max": 2, "games": ["snake", "space"], "bc_per_continue": 0}'::jsonb)""")
    t("vidéo de continuation autorisée (Snake)", lambda: as_user(c, U2, "select rewarded_continue('snake')")[0][0])
    t("jeu non éligible refusé (BoyBlocks)", lambda: must_fail(lambda: as_user(c, U2, "select rewarded_continue('boyblocks')"), "game not eligible"))
    as_user(c, U2, "select rewarded_continue('space')")
    t("limite quotidienne de vidéos", lambda: must_fail(lambda: as_user(c, U2, "select rewarded_continue('snake')"), "daily limit"))
    before = sql("select (select count(*) from scores), (select bc from player_stats where user_id = %s), (select count(*) from leaderboard('snake', null, 50))", (U2,))[0]
    t("score continué : XP de participation, 0 BC, hors classement", lambda: as_user(c, U2, "select submit_continued_score('snake', 40, 1)")[0][0])
    after = sql("select (select count(*) from scores), (select bc from player_stats where user_id = %s), (select count(*) from leaderboard('snake', null, 50))", (U2,))[0]
    t("classement, scores et BC inchangés", lambda: (before, after) if before == after else (_ for _ in ()).throw(Exception(f"{before} -> {after}")))
    t("trop de continuations refusé", lambda: must_fail(lambda: (sql("update scores_continued set created_at = now() - interval '1 minute'"), as_user(c, U2, "select submit_continued_score('snake', 40, 2)"))[1], "invalid continues"))
    t("abonnement refusé à un joueur", lambda: must_fail(lambda: as_user(c, U2, "select staff_premium_set('joh', 30)"), "forbidden"))
    t("Premium simulé pour joh + badge Pionnier", lambda: as_user(c, U1, "select staff_premium_set('joh', 30)")[0][0])
    t("me() : premium", lambda: as_user(c, U2, "select me()->'premium'")[0][0])
    t("fiche publique : premium visible", lambda: as_user(c, U2, "select public_profile('joh')->'premium'")[0][0])
    sql("update shop_items set premium_only = true where code = 'title_legend'")
    t("cosmétique Premium refusé à un non-abonné", lambda: must_fail(lambda: as_user(c, U1, "select buy_item('title_legend')"), "premium only"))
    t("résiliation : plus Premium, badge Pionnier conservé", lambda: (as_user(c, U1, "select staff_premium_set('joh', 0)")[0][0], sql("select count(*) from user_badges where badge_code = 'premium_pioneer'")[0][0]))
    t("Premium : rien qui touche au jeu (aucune fonction de score ne lit is_premium)", lambda: sql("select string_agg(proname, ',') from pg_proc where pronamespace = 'public'::regnamespace and proname in ('submit_score','bb_award','boyblocks_finish','claim_daily','claim_mission') and prosrc ilike '%premium%'")[0][0] or "aucune")
    t("journal : changements de monétisation tracés", lambda: sql("select count(*) from economy_log where what like 'monetisation:%' or what like 'premium:%'")[0][0])

    print("== v13 : file de validation marketing")
    sql("insert into marketing_ingest_keys (hash, label) values (encode(sha256(convert_to('jeton-de-test-0123456789abcdef0123456789', 'UTF8')), 'hex'), 'test') on conflict do nothing")
    def as_service(q, a=None):
        with c.cursor() as cur:
            cur.execute("begin"); cur.execute("set local role service_role"); cur.execute(q, a); r = cur.fetchall(); cur.execute("commit"); return r
    t("jeton correct reconnu", lambda: as_service("select marketing_token_ok('jeton-de-test-0123456789abcdef0123456789')")[0][0] or (_ for _ in ()).throw(Exception("refusé")))
    t("mauvais jeton refusé", lambda: (not as_service("select marketing_token_ok('mauvais-jeton-0123456789abcdef0123456789')")[0][0]) or (_ for _ in ()).throw(Exception("accepté")))
    meta = json.dumps({"run_id": "gh-1", "game": "boyblocks", "duree": 28, "partie": {"score": 606}, "textes": {"accroche": "Satisfaisant", "legende": "606 points", "hashtags": ["#BOYGAMES", "#puzzle"], "source": "modèles"}})
    t("vidéo enregistrée « à valider »", lambda: as_service("select marketing_register(%s::jsonb, 'gh-1/video.mp4', 'gh-1/poster.jpg')", (meta,))[0][0])
    t("même passage : pas de doublon", lambda: as_service("select marketing_register(%s::jsonb, 'gh-1/video.mp4', null)", (meta,))[0][0])
    t("dépôt impossible pour un joueur", lambda: must_fail(lambda: as_user(c, U2, "select marketing_register('{}'::jsonb, 'x', null)"), "permission denied"))
    t("file illisible pour un joueur", lambda: must_fail(lambda: as_user(c, U2, "select staff_marketing(null)"), "forbidden"))
    vid = as_user(c, U1, "select staff_marketing(null)")[0][0]["videos"][0]["id"]
    t("validation avec date + texte corrigé → posts créés par réseau", lambda: (as_user(c, U1, "select staff_marketing_review(%s, 'validee', now() + interval '2 days', 'Nouvelle accroche', null, null, '')", (vid,)),
        sorted(p["platform"] for p in as_user(c, U1, "select staff_marketing(null)")[0][0]["videos"][0]["posts"]))[1])
    t("revalidation : pas de post en double", lambda: (as_user(c, U1, "select staff_marketing_review(%s, 'validee', null, null, null, null, '')", (vid,)), sql("select count(*) from marketing_posts")[0][0])[1])
    t("refus", lambda: (as_user(c, U1, "select staff_marketing_review(%s, 'refusee', null, null, null, null, 'trop sombre')", (vid,)), as_user(c, U1, "select staff_marketing('refusee')")[0][0]["counts"])[1])
    t("mode auto : plateforme inconnue refusée", lambda: must_fail(lambda: as_user(c, U1, """select staff_marketing_settings('{"enabled": true, "per_day": 1, "hour": 18, "platforms": ["myspace"]}'::jsonb)"""), "invalid platform"))
    t("mode auto reste désactivé par défaut", lambda: as_user(c, U1, "select staff_marketing(null)")[0][0]["settings"]["auto"]["enabled"] is False or (_ for _ in ()).throw(Exception("activé")))

    print("== v14 : BoyBlocks 9x9 (essai)")
    def playout9(seed, limit=40):
        mv = []
        for _ in range(limit):
            if sql("select over from bb_replay_n(%s, %s::jsonb, true, 2, 9)", (seed, json.dumps(mv)))[0][0]: break
            nxt = None
            for slot in range(3):
                for rr in range(9):
                    for cc in range(9):
                        if sql("select ok from bb_replay_n(%s, %s::jsonb, true, 2, 9)", (seed, json.dumps(mv + [[slot, rr, cc]])))[0][0]:
                            nxt = [slot, rr, cc]; break
                    if nxt: break
                if nxt: break
            if not nxt: break
            mv.append(nxt)
        return mv
    t("réglage lisible par un visiteur (9x9 activé)", lambda: as_user(c, None, "select game_settings_public()")[0][0])
    lb8 = sql("select count(*) from leaderboard('boyblocks', null, 50)")[0][0]
    r9 = as_user(c, U2, "select boyblocks_start_v3(9)")[0][0]
    t("partie 9x9 classée créée", lambda: {k: r9[k] for k in ("size", "rules")})
    mv9 = playout9(r9["seed"], 30)
    sql("update boyblocks_runs set started_at = now() - interval '10 minutes' where id = %s", (r9["run_id"],))
    t("fin de partie 9x9 vérifiée par la base", lambda: {k: v for k, v in as_user(c, U2, "select boyblocks_finish(%s, %s::jsonb)", (r9["run_id"], json.dumps(mv9)))[0][0].items() if k in ("score", "moves", "size")})
    t("score 9x9 rangé à part (« boyblocks9 »)", lambda: sql("select game, count(*) from scores where game like 'boyblocks%%' group by game order by game"))
    t("classement 8x8 inchangé", lambda: (lb8, sql("select count(*) from leaderboard('boyblocks', null, 50)")[0][0]) if lb8 == sql("select count(*) from leaderboard('boyblocks', null, 50)")[0][0] else (_ for _ in ()).throw(Exception("modifié")))
    t("classement 9x9 séparé", lambda: as_user(c, U2, "select pseudo, score from leaderboard('boyblocks9', null, 10)"))
    r9b = as_user(c, U2, "select boyblocks_start_v3(9)")[0][0]
    sql("update boyblocks_runs set started_at = now() - interval '10 minutes' where id = %s", (r9b["run_id"],))
    t("coup impossible sur la grille 9x9 refusé", lambda: must_fail(lambda: as_user(c, U2, "select boyblocks_finish(%s, '[[0,9,9]]'::jsonb)", (r9b["run_id"],)), "invalid run"))
    t("interrupteur refusé à un joueur", lambda: must_fail(lambda: as_user(c, U2, """select staff_game_settings_set('boyblocks9', '{"enabled": false}'::jsonb)"""), "forbidden"))
    as_user(c, U1, """select staff_game_settings_set('boyblocks9', '{"enabled": false}'::jsonb)""")
    t("retour au 8x8 : nouvelle partie 9x9 refusée", lambda: must_fail(lambda: as_user(c, U2, "select boyblocks_start_v3(9)"), "grid disabled"))
    t("retour au 8x8 : partie 8x8 toujours possible", lambda: as_user(c, U2, "select boyblocks_start_v3(8)->>'size'")[0][0])
    t("scores 9x9 conservés après le retour au 8x8", lambda: sql("select count(*) from scores where game = 'boyblocks9'")[0][0])
    as_user(c, U1, """select staff_game_settings_set('boyblocks9', '{"enabled": true}'::jsonb)""")
    t("paliers 9x9 définis", lambda: sql("select count(*) from badge_tracks where game = 'boyblocks9'")[0][0])
    t("favori « boyblocks9 » accepté s'il est débloqué", lambda: (as_user(c, U2, "select sync_tiers()"), sql("insert into user_tiers (user_id, game, tier) values (%s, 'boyblocks9', 0) on conflict do nothing", (U2,)), as_user(c, U2, "select set_favorites(array['boyblocks9:0'])"), sql("select favorites from profiles where id = %s", (U2,))[0][0])[3])

    print("== v15 : questionnaire bêta")
    t("pas encore de réponses", lambda: as_user(c, U2, "select beta_survey_get()")[0][0] is None or (_ for _ in ()).throw(Exception("pas vide")))
    t("brouillon enregistré", lambda: as_user(c, U2, """select beta_survey_save('{"q_snake_speed": "trop_rapide", "q_tactile_pb": ["zoom", "defile"], "g_space": "non"}'::jsonb, '', false, 1)->>'ok'""")[0][0])
    t("brouillon relu (non envoyé)", lambda: (lambda r: (r["answers"]["q_tactile_pb"], r["completed_at"]))(as_user(c, U2, "select beta_survey_get()")[0][0]))
    t("envoi avec commentaire", lambda: as_user(c, U2, """select beta_survey_save('{"q_snake_speed": "parfaite", "q_tactile_pb": ["zoom"]}'::jsonb, 'Super jeu !', true, 1)->>'completed_at' is not null""")[0][0])
    t("modification après envoi : une seule ligne, réponse remplacée", lambda: (as_user(c, U2, """select beta_survey_save('{"q_snake_speed": "un_peu_rapide"}'::jsonb, 'Super jeu !', false, 1)"""),
        sql("select count(*), max(answers->>'q_snake_speed'), bool_and(completed_at is not null) from beta_survey where user_id = %s", (U2,))[0])[1])
    t("valeur libre refusée (pas de texte arbitraire)", lambda: must_fail(lambda: as_user(c, U2, """select beta_survey_save('{"q_snake_speed": "<script>"}'::jsonb)"""), "invalid answers"))
    t("clé invalide refusée", lambda: must_fail(lambda: as_user(c, U2, """select beta_survey_save('{"Q SNAKE": "x"}'::jsonb)"""), "invalid answers"))
    t("liste trop longue refusée", lambda: must_fail(lambda: as_user(c, U2, """select beta_survey_save('{"q": ["a","b","c","d","e","f","g","h","i","j","k"]}'::jsonb)"""), "invalid answers"))
    t("commentaire trop long refusé", lambda: must_fail(lambda: as_user(c, U2, "select beta_survey_save('{}'::jsonb, repeat('x', 2001))"), "comment too long"))
    t("visiteur refusé", lambda: must_fail(lambda: as_user(c, None, "select beta_survey_save('{}'::jsonb)"), "permission denied"))
    t("réponses d'équipe refusées à un joueur", lambda: must_fail(lambda: as_user(c, U2, "select staff_beta_survey()"), "forbidden"))
    t("table illisible en direct", lambda: must_fail(lambda: as_user(c, U2, "select * from beta_survey"), "permission denied"))
    t("équipe : réponses avec pseudo", lambda: [(r["pseudo"], r["answers"], r["comment"]) for r in as_user(c, U1, "select staff_beta_survey()")[0][0]])

    print("== v20 : fiche joueur + journal des interventions")
    fiche = as_user(c, U1, "select staff_player_detail('joh')")[0][0]
    t("fiche : profil, stats, badges, records, bêta, signalements, bugs, historique", lambda: sorted(fiche.keys()))
    t("fiche : ni e-mail, ni mot de passe, ni message privé", lambda: (not any(k in json.dumps(fiche).lower() for k in ["@", "password", "encrypted", "messages"])) or (_ for _ in ()).throw(Exception("fuite")))
    t("fiche refusée à un joueur", lambda: must_fail(lambda: as_user(c, U2, "select staff_player_detail('tintintest')"), "forbidden"))
    t("fiche : joueur inconnu", lambda: must_fail(lambda: as_user(c, U1, "select staff_player_detail('personne')"), "unknown player"))
    as_user(c, U1, "select staff_ban('joh', 'essai journal', 1)"); as_user(c, U1, "select staff_unban('joh')")
    as_user(c, U1, "select staff_beta_remove('joh')"); as_user(c, U1, "select staff_beta_add('joh')")
    hist = as_user(c, U1, "select staff_player_detail('joh')->'history'")[0][0]
    t("journal : suspension, réactivation, retrait et ajout bêta, avec l'auteur", lambda: [(h["action"], h["by"]) for h in hist[:4]])
    t("journal illisible et non modifiable par un joueur", lambda: must_fail(lambda: as_user(c, U2, "delete from admin_actions"), "permission denied"))
    t("aucune donnée modifiée par la fiche (BC, XP inchangés)", lambda: sql("select bc, xp from player_stats where user_id = %s", (U2,))[0])

    print("== v19 : liste des joueurs (équipe)")
    nb_profils = sql("select count(*) from profiles")[0][0]
    pl = as_user(c, U1, "select staff_players()")[0][0]
    t("tous les comptes listés, même sans partie", lambda: (len(pl), nb_profils, sorted(x["pseudo"] for x in pl if x["games"] == 0)) if len(pl) == nb_profils else (_ for _ in ()).throw(Exception("manquants")))
    t("aucune adresse e-mail renvoyée", lambda: not any("@" in json.dumps(x) for x in pl) or (_ for _ in ()).throw(Exception("e-mail")))
    t("refusé à un joueur", lambda: must_fail(lambda: as_user(c, U2, "select staff_players()"), "forbidden"))
    t("refusé à un visiteur", lambda: must_fail(lambda: as_user(c, None, "select staff_players()"), "permission denied"))

    print("== v18 : invitations bêta")
    sql("update app_settings set value = '{\"on\": true}' where key = 'beta'")
    inv = as_user(c, U1, "select staff_beta_invite_create(2, 7, 'Mathis et Léa')")[0][0]
    t("code créé (8 caractères lisibles)", lambda: (inv["code"], inv["max_uses"]) if len(inv["code"]) == 8 and inv["code"].isalnum() else (_ for _ in ()).throw(Exception(inv)))
    t("création refusée à un joueur", lambda: must_fail(lambda: as_user(c, U3, "select staff_beta_invite_create(1, 7, '')"), "forbidden"))
    t("valeurs hors bornes refusées", lambda: must_fail(lambda: as_user(c, U1, "select staff_beta_invite_create(51, 7, '')"), "invalid value"))
    sql("delete from beta_members where user_id = %s", (U3,))
    t("hors bêta : accès refusé avant le code", lambda: must_fail(lambda: as_user(c, U3, "select beta_space()"), "beta"))
    t("mauvais code = refus enregistré", lambda: as_user(c, U3, "select beta_redeem('ZZZZZZZZ')->>'status'")[0][0])
    t("bon code (minuscules et tiret acceptés) = admis", lambda: as_user(c, U3, "select beta_redeem(%s)->>'status'", (inv["code"][:4].lower() + "-" + inv["code"][4:],))[0][0])
    t("après le code : accès à l'espace bêta", lambda: as_user(c, U3, "select beta_space()->>'version'")[0][0])
    t("deuxième utilisation par le même = déjà admis, compteur inchangé", lambda: (as_user(c, U3, "select beta_redeem(%s)->>'status'", (inv["code"],))[0][0], sql("select uses from beta_invites where code = %s", (inv["code"],))[0][0]))
    t("liste équipe : usages et pseudo", lambda: [(x["uses"], x["players"]) for x in as_user(c, U1, "select staff_beta_invites()")[0][0] if x["code"] == inv["code"]])
    t("liste refusée à un joueur", lambda: must_fail(lambda: as_user(c, U3, "select staff_beta_invites()"), "forbidden"))
    t("table des codes illisible en direct", lambda: must_fail(lambda: as_user(c, U3, "select * from beta_invites"), "permission denied"))
    t("visiteur refusé", lambda: must_fail(lambda: as_user(c, None, "select beta_redeem('ABCDEFGH')"), "permission denied"))
    one = as_user(c, U1, "select staff_beta_invite_create(1, 1, '')")[0][0]["code"]
    sql("update beta_invites set uses = 1 where code = %s", (one,))
    sql("delete from beta_members where user_id = %s", (U3,))
    t("code épuisé refusé", lambda: as_user(c, U3, "select beta_redeem(%s)->>'status'", (one,))[0][0])
    sql("update beta_invites set uses = 0, expires_at = now() - interval '1 minute' where code = %s", (one,))
    t("code expiré refusé", lambda: as_user(c, U3, "select beta_redeem(%s)->>'status'", (one,))[0][0])
    as_user(c, U1, "select staff_beta_invite_revoke(%s)", (inv["code"],))
    t("code révoqué refusé", lambda: as_user(c, U3, "select beta_redeem(%s)->>'status'", (inv["code"],))[0][0])
    for _ in range(10): as_user(c, U3, "select beta_redeem('YYYYYYYY')")
    t("anti-devinette : 10 essais ratés par heure", lambda: as_user(c, U3, "select beta_redeem('XXXXXXXX')->>'status'")[0][0])
    sql("delete from beta_invite_fails"); sql("insert into beta_members (user_id) values (%s) on conflict do nothing", (U3,))
    sql("update app_settings set value = '{\"on\": false}' where key = 'beta'")

    print("== v22 : ticket de partie, scores vraisemblables")
    t("envoi direct de score fermé aux joueurs", lambda: must_fail(lambda: as_user(c, U2, "select submit_score('snake', 10)"), "permission denied"))
    t("partie normale acceptée (Snake 40 pommes en 5 min)", lambda: play(U2, "snake", 40, 300)["xp"])
    t("score impossible refusé (Snake 300 pommes en 10 s)", lambda: must_fail(lambda: play(U2, "snake", 300, 10), "implausible score"))
    t("Space 100 000 en 10 s refusé", lambda: must_fail(lambda: play(U2, "space", 99000, 10), "implausible score"))
    t("Block Drop 14 100 en 5 min accepté", lambda: play(U2, "blocks", 14100, 300)["xp"])
    rid = as_user(c, U2, "select game_start('snake')")[0][0]
    sql("update game_runs set started_at = now() - interval '5 minutes' where id = %s", (rid,)); sql("update scores set created_at = now() - interval '1 minute' where user_id = %s", (U2,))
    as_user(c, U2, "select submit_score_v2('snake', 5, %s)", (rid,))
    t("ticket utilisable une seule fois", lambda: must_fail(lambda: as_user(c, U2, "select submit_score_v2('snake', 5, %s)", (rid,)), "invalid run"))
    rid2 = as_user(c, U2, "select game_start('space')")[0][0]
    t("ticket d'un autre jeu refusé", lambda: must_fail(lambda: as_user(c, U2, "select submit_score_v2('snake', 5, %s)", (rid2,)), "invalid run"))
    t("ticket d'un autre joueur refusé", lambda: must_fail(lambda: as_user(c, U1, "select submit_score_v2('space', 5, %s)", (rid2,)), "invalid run"))
    t("jeu inconnu refusé", lambda: must_fail(lambda: as_user(c, U2, "select game_start('boyblocks')"), "unknown game"))
    t("visiteur refusé", lambda: must_fail(lambda: as_user(c, None, "select game_start('snake')"), "permission denied"))
    t("tickets illisibles en direct", lambda: must_fail(lambda: as_user(c, U2, "select * from game_runs"), "permission denied"))

    print("== v17 : plafond Space Attack")
    t("score Space 45 000 accepté (bloqué à 20 000 avant)", lambda: play(U2, "space", 45000)["xp"])
    t("score Space au-delà de 100 000 refusé", lambda: must_fail(lambda: play(U2, "space", 100001), "invalid score"))
    t("plafond Snake inchangé", lambda: must_fail(lambda: play(U2, "snake", 430), "invalid score"))

    print("== v16 : espace bêta, missions, badge sur validation")
    t("migration : aucun badge attribué automatiquement", lambda: (badges_avant, badges_apres) if badges_avant == badges_apres else (_ for _ in ()).throw(Exception("badges modifiés")))
    t("badge beta_tester exclusif, beta_founder intact", lambda: sql("select code, exclusive from badges where code in ('beta_tester','beta_founder') order by code"))
    sp = as_user(c, U2, "select beta_space()")[0][0]
    t("espace : 11 missions, rien de rempli, preuves présentes", lambda: (len(sp["codes"]), sp["missions"], sorted(sp["evidence"].keys())[:4], sp["eligible"]))
    t("mission enregistrée", lambda: as_user(c, U2, "select beta_mission_set('snake', 'reussi', 'RAS')->>'ok'")[0][0])
    t("mission modifiée (une seule ligne)", lambda: (as_user(c, U2, "select beta_mission_set('snake', 'probleme', 'virage raté')"), sql("select count(*), max(status) from beta_missions where user_id = %s and code = 'snake'", (U2,))[0])[1])
    t("mission inconnue refusée", lambda: must_fail(lambda: as_user(c, U2, "select beta_mission_set('pirate', 'reussi')"), "unknown mission"))
    t("statut inconnu refusé", lambda: must_fail(lambda: as_user(c, U2, "select beta_mission_set('snake', 'parfait')"), "invalid status"))
    t("visiteur refusé", lambda: must_fail(lambda: as_user(c, None, "select beta_space()"), "permission denied"))
    t("table missions illisible en direct", lambda: must_fail(lambda: as_user(c, U2, "select * from beta_missions"), "permission denied"))
    t("fonctions internes non appelables", lambda: must_fail(lambda: as_user(c, U2, "select beta_eligible(auth.uid())"), "permission denied"))
    t("suivi refusé à un joueur", lambda: must_fail(lambda: as_user(c, U2, "select staff_beta_overview()"), "forbidden"))
    t("validation refusée à un joueur", lambda: must_fail(lambda: as_user(c, U2, "select staff_beta_validate('joh', 'valide')"), "forbidden"))
    t("badge refusé si pas éligible (missions incomplètes)", lambda: must_fail(lambda: as_user(c, U1, "select staff_beta_validate('joh', 'valide')"), "not eligible"))
    for code in ["compte", "snake", "boyblocks", "space", "multi", "amis", "boybot", "classements", "progression", "mobile", "questionnaire"]:
        as_user(c, U2, "select beta_mission_set(%s, %s)", (code, "impossible" if code == "multi" else "reussi"))
    t("missions remplies mais questionnaire non envoyé = pas éligible", lambda: (sql("update beta_survey set completed_at = null where user_id = %s", (U2,)), as_user(c, U2, "select beta_space()->>'eligible'")[0][0])[1])
    sql("update beta_survey set completed_at = now() where user_id = %s", (U2,))
    t("éligible sans avoir trouvé de bug", lambda: (as_user(c, U2, "select beta_space()->>'eligible'")[0][0], sql("select count(*) from bug_reports where user_id = %s", (U2,))[0][0]))
    ov = as_user(c, U1, "select staff_beta_overview()")[0][0]
    t("suivi : testeur listé sans e-mail", lambda: [(x["pseudo"], x["eligible"], "email" in json.dumps(x)) for x in ov["testers"]])
    t("validation « à revoir » sans badge", lambda: (as_user(c, U1, "select staff_beta_validate('joh', 'a_revoir', 'commentaires trop courts')"), sql("select count(*) from user_badges where badge_code = 'beta_tester'")[0][0])[1])
    t("validation finale : badge attribué + notification", lambda: (as_user(c, U1, "select staff_beta_validate('joh', 'valide', 'merci')")[0][0], sql("select count(*) from notifications where user_id = %s and kind = 'badge'", (U2,))[0][0]))
    t("badge unique (pas de doublon)", lambda: (as_user(c, U1, "select staff_beta_validate('joh', 'valide')")[0][0]["badge_added"], sql("select count(*) from user_badges where badge_code = 'beta_tester' and user_id = %s", (U2,))[0][0]))
    t("badge permanent (non supprimable)", lambda: must_fail(lambda: sql("delete from user_badges where badge_code = 'beta_tester'"), "permanent"))
    t("nouvelle manche : missions repartent à zéro, anciennes gardées", lambda: (as_user(c, U1, "select staff_beta_new_round()")[0][0], as_user(c, U2, "select beta_space()->'missions'")[0][0], sql("select count(*) from beta_missions where version = 1")[0][0]))
    t("badge conservé après la nouvelle manche", lambda: as_user(c, U2, "select beta_space()->>'badge'")[0][0])

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

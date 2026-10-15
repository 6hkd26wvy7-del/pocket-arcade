"""Deux vérifications sur une base locale jetable (jamais Supabase) :
1. installation neuve avec sql/schema_all.sql seul, puis relance des deux migrations par-dessus ;
2. le rejeu SQL de BoyBlocks donne exactement le même résultat que le moteur JS (300 parties de gen.mjs).
Lancer : python3 sql/test/test_installation_et_moteur.py   (Node doit être installé pour la partie 2)"""
import os, sys, shutil, subprocess
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import *

HERE = os.path.dirname(os.path.abspath(__file__))
fail = 0
srv, d = start(); c = connect(srv)
def sql(q, a=None):
    with c.cursor() as cur:
        cur.execute(q, a)
        try: return cur.fetchall()
        except psycopg2.ProgrammingError: return None
try:
    sql(STUB)
    run_file(c, f"{REPO}/schema_all.sql"); print("OK  installation neuve (schema_all.sql)")
    sql(SEED)
    for f in ["schema_v6_v7.sql", "schema_v8_v9.sql", "schema_v6_v7.sql"]:
        run_file(c, f"{REPO}/{f}"); print("OK  relance", f)
    for fn in ["boyblocks_start()", "my_tiers()", "sync_tiers()"]:
        if not sql(f"select has_function_privilege('authenticated', 'public.{fn}', 'execute')")[0][0]:
            print("ECHEC", fn, "n'est plus appelable"); fail += 1
    print("OK  fonctions BoyBlocks / paliers toujours appelables" if not fail else "")

    node = shutil.which("node") or os.path.expanduser("~/.local/node/bin/node")
    if not os.path.exists(node):
        print("SAUTÉ comparaison moteur JS / SQL : Node introuvable")
    else:
        sql(subprocess.check_output([node, os.path.join(HERE, "gen.mjs")], text=True))
        rows = sql("""select x.i, x.score, r.score, x.lines, r.lines, x.bs, r.best_streak, x.over, r.over, r.ok, r.err
                      from xt x, lateral bb_replay(x.seed, x.mv, x.ens) r order by x.i""")
        bad = [r for r in rows if not r[9] or (r[1], r[3], r[5], r[7]) != (r[2], r[4], r[6], r[8])]
        for r in bad[:5]: print("  écart partie", r)
        print(f"{'OK ' if not bad else 'ECHEC'} moteur JS = rejeu SQL sur {len(rows)} parties ({len(bad)} écart(s))")
        fail += len(bad)
finally:
    c.close(); srv.cleanup(); shutil.rmtree(d, ignore_errors=True)
sys.exit(1 if fail else 0)

"""Simule un éditeur SQL qui exécuterait les migrations instruction par instruction (chacune validée seule).
Attendu : le script s'arrête au garde-fou AVANT toute modification. Lancer : python3 sql/test/test_execution_morcelee.py
(pip install pgserver psycopg2-binary sqlparse)"""
import os, sys, shutil, sqlparse
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from harness import *
fail = 0
for mig, marker in [("schema_v6_v7.sql", "public.avatars"), ("schema_v8_v9.sql", "public.bb_shapes"), ("schema_v10_boyblocks_regles2.sql", "public.bb_deal2"), ("schema_v11_economie_reglages.sql", "public.economy_settings"), ("schema_v12_monetisation.sql", "public.monetization_settings"), ("schema_v14_boyblocks_9x9.sql", "public.game_settings"), ("schema_v15_questionnaire.sql", "public.beta_survey"), ("schema_v16_espace_beta.sql", "public.beta_missions"), ("schema_v18_invitations.sql", "public.beta_invites")]:
    srv, d = start(); c = connect(srv)
    try:
        with c.cursor() as cur: cur.execute(STUB)
        for f in ["schema_v1_v4.sql", "schema_v5.sql", "schema_v6a_sauvegarde.sql"]: run_file(c, f"{HIST}/{f}")
        with c.cursor() as cur: cur.execute(SEED)
        if mig != "schema_v6_v7.sql": run_file(c, f"{REPO}/schema_v6_v7.sql")
        if mig in ("schema_v10_boyblocks_regles2.sql", "schema_v11_economie_reglages.sql", "schema_v12_monetisation.sql", "schema_v14_boyblocks_9x9.sql", "schema_v15_questionnaire.sql", "schema_v16_espace_beta.sql", "schema_v18_invitations.sql"): run_file(c, f"{REPO}/schema_v8_v9.sql")
        if mig in ("schema_v11_economie_reglages.sql", "schema_v12_monetisation.sql", "schema_v14_boyblocks_9x9.sql", "schema_v15_questionnaire.sql", "schema_v16_espace_beta.sql", "schema_v18_invitations.sql"): run_file(c, f"{REPO}/schema_v10_boyblocks_regles2.sql")
        if mig in ("schema_v12_monetisation.sql", "schema_v14_boyblocks_9x9.sql", "schema_v15_questionnaire.sql", "schema_v16_espace_beta.sql", "schema_v18_invitations.sql"): run_file(c, f"{REPO}/schema_v11_economie_reglages.sql")
        if mig in ("schema_v14_boyblocks_9x9.sql", "schema_v15_questionnaire.sql", "schema_v16_espace_beta.sql", "schema_v18_invitations.sql"): run_file(c, f"{REPO}/schema_v12_monetisation.sql"); run_file(c, f"{REPO}/schema_v13_marketing.sql")
        if mig in ("schema_v15_questionnaire.sql", "schema_v16_espace_beta.sql", "schema_v18_invitations.sql"): run_file(c, f"{REPO}/schema_v14_boyblocks_9x9.sql")
        if mig in ("schema_v16_espace_beta.sql", "schema_v18_invitations.sql"): run_file(c, f"{REPO}/schema_v15_questionnaire.sql")
        if mig == "schema_v18_invitations.sql": run_file(c, f"{REPO}/schema_v16_espace_beta.sql"); run_file(c, f"{REPO}/schema_v17_plafond_space.sql")
        # chaque instruction dans sa propre transaction : les "begin;" / "commit;" du script sont perdus
        stmts = [s for s in sqlparse.split(open(f"{REPO}/{mig}").read()) if s.strip() and sqlparse.format(s, strip_comments=True).strip().rstrip(";").lower() not in ("begin", "commit")]
        err = None
        for s in stmts:
            try:
                with c.cursor() as cur: cur.execute(s)
            except Exception as e:
                err = str(e).splitlines()[0]; break
        with c.cursor() as cur:
            cur.execute("select coalesce(to_regclass(%s)::text, to_regproc(%s)::text)", (marker, marker)); created = cur.fetchone()[0]
        ok = err and "PLUSIEURS MORCEAUX" in err and created is None
        print(("OK   " if ok else "ECHEC"), mig, "| arrêt :", err, "| modification appliquée :", created is not None)
        fail += not ok
    finally:
        c.close(); srv.cleanup(); shutil.rmtree(d, ignore_errors=True)
sys.exit(1 if fail else 0)

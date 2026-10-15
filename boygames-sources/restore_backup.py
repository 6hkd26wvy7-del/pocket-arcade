#!/usr/bin/env python3
"""Restaure un fichier de sauvegarde BOYGAMES dans une base Postgres VIDE (schema deja cree).
Usage: restore.py export.json | psql ...   (affiche du SQL)"""
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
data = d["data"] if "data" in d else d   # accepte le nouveau format (v2) et l ancien export (liste de tables a plat)
order = ["profiles","player_stats","scores","bc_ledger","user_badges","user_items","login_streaks","friendships","messages",
         "notifications","season_claims","mission_claims","reports","bans","user_roles","beta_members","news","banned_words","app_settings","blocks","bug_reports"]
print("begin;")
print("set session_replication_role = replica;")      # evite les triggers (badges, stats) pendant la restauration
for t in order:
    rows = data.get(t) or []
    if not rows: continue
    tag = "$J" + t + "$"
    js = json.dumps(rows, ensure_ascii=False)
    print(f"truncate public.{t} cascade;" if t in ("banned_words","app_settings","news") else "")
    print(f"insert into public.{t} overriding system value select * from jsonb_populate_recordset(null::public.{t}, {tag}{js}{tag}::jsonb);")
print("commit;")

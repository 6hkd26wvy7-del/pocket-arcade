"""Base PostgreSQL jetable (pip install pgserver psycopg2-binary) qui imite Supabase, pour essayer les migrations BOYGAMES sans toucher a Supabase."""
import os, sys, json, shutil, tempfile
import pgserver, psycopg2

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
V6A = os.path.join(REPO, "schema_v6a_sauvegarde.sql")

STUB = """
create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
grant usage on schema public to anon, authenticated, service_role;
-- comme Supabase : droits automatiques sur tout ce qui sera cree dans public
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
create schema auth;
grant usage on schema auth to anon, authenticated, service_role;
create table auth.users (id uuid primary key default gen_random_uuid(), email text);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant execute on function auth.uid() to anon, authenticated, service_role;
"""

U1 = "aaaaaaaa-0000-4000-8000-000000000001"  # tintintest (fondateur)
U2 = "aaaaaaaa-0000-4000-8000-000000000002"  # joh (beta)
U3 = "aaaaaaaa-0000-4000-8000-000000000003"  # joueur de test supplementaire

SEED = f"""
insert into auth.users (id) values ('{U1}'), ('{U2}'), ('{U3}');
insert into public.profiles (id, pseudo, country) values ('{U1}','tintintest','FR'), ('{U2}','joh','FR'), ('{U3}','zed_test','FR');
insert into public.player_stats (user_id) values ('{U1}'), ('{U2}'), ('{U3}') on conflict do nothing;
insert into public.user_roles (user_id, role) values ('{U1}', 'founder');
insert into public.beta_members (user_id) values ('{U2}'), ('{U3}');
insert into public.scores (user_id, game, score) values ('{U1}','snake',24), ('{U1}','blocks',14100), ('{U1}','space',4192), ('{U2}','snake',13);
insert into public.user_badges (user_id, badge_code) values ('{U1}','first_game'), ('{U2}','first_game');
insert into public.friendships (user_a, user_b, requested_by, status) values (least('{U1}'::uuid,'{U2}'::uuid), greatest('{U1}'::uuid,'{U2}'::uuid), '{U1}', 'accepted');
insert into public.messages (from_id, to_id, body) values ('{U1}','{U2}','salut');
update public.player_stats set bc = 27, xp = 383, level = 3 where user_id = '{U1}';
"""


def start():
    d = tempfile.mkdtemp(prefix="boygames-pg-")
    srv = pgserver.get_server(d, cleanup_mode="stop")
    return srv, d


def connect(srv):
    c = psycopg2.connect(srv.get_uri())
    c.autocommit = True
    return c


def run_file(c, path):
    with c.cursor() as cur:
        cur.execute(open(path).read())
        try:
            return cur.fetchall()
        except psycopg2.ProgrammingError:
            return None


def as_user(c, uid, sql, args=None):
    """Execute sql comme un joueur connecte (role authenticated) ou un visiteur (uid=None -> anon)."""
    with c.cursor() as cur:
        cur.execute("begin")
        cur.execute("set local role " + ("authenticated" if uid else "anon"))
        cur.execute("select set_config('request.jwt.claim.sub', %s, true)", (uid or "",))
        try:
            cur.execute(sql, args)
            try:
                rows = cur.fetchall()
            except psycopg2.ProgrammingError:
                rows = None
            cur.execute("commit")
            return rows
        except Exception:
            cur.execute("rollback")
            raise

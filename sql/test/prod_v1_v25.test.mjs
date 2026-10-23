// Mise à niveau de la PRODUCTION v1 → v25 en un seul bloc, essayée sur PostgreSQL local (PGlite), jamais sur Supabase.
// Usage : node prod_v1_v25.test.mjs <fichier.sql>
import assert from "node:assert/strict";
import fs from "node:fs";
import { fileURLToPath } from "node:url";
import { PGlite } from "@electric-sql/pglite";
const read = (rel) => fs.readFileSync(fileURLToPath(new URL(rel, import.meta.url)), "utf8");
const big = fs.readFileSync(process.argv[2], "utf8");
const db = new PGlite();
await db.exec(`create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
grant usage on schema public to anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
create schema auth; grant usage on schema auth to anon, authenticated, service_role;
create table auth.users (id uuid primary key default gen_random_uuid(), email text, last_sign_in_at timestamptz, email_confirmed_at timestamptz);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
grant execute on function auth.uid() to anon, authenticated, service_role;`);
await db.exec(read("../historique/schema.sql"));   // état réel de la production : v1 (profiles + scores)
const tables = (await db.query("select count(*)::int n from pg_tables where schemaname='public'")).rows[0].n;
assert.equal(tables, 2, "la v1 locale doit avoir 2 tables comme la production");
const ids = [];
for (let i = 1; i <= 5; i++) { const id = `dddddddd-0000-4000-8000-00000000000${i}`; ids.push(id);
  await db.exec(`insert into auth.users (id) values ('${id}'); insert into public.profiles (id, pseudo, country, created_at) values ('${id}', 'prod_${i}', '${i % 2 ? "FR" : "OTHER"}', now() - interval '9 days');`); }
for (let k = 0; k < 99; k++) await db.exec(`insert into public.scores (user_id, game, score, created_at) values ('${ids[k % 5]}', 'snake', ${(k * 7) % 300}, now() - interval '${k + 60} hours')`);
const fp = async () => (await db.query("select md5(string_agg(id::text||'|'||user_id||'|'||game||'|'||score::text||'|'||created_at::text, ',' order by id)) s from public.scores")).rows[0].s;
const before = await fp();

const t0 = Date.now();
const res = await db.exec(big);
const last = res[res.length - 1].rows[0];
console.log("résultat :", JSON.stringify(last), (Date.now() - t0) + " ms");
assert.equal(last.resultat, "production v25 appliquée");
assert.equal(Number(last.profils), 5); assert.equal(Number(last.scores), 99);
assert.equal(await fp(), before, "scores intacts");
assert.equal((await db.query("select (value->>'on')::boolean b from public.app_settings where key='beta'")).rows[0].b, false);

async function as(uid, sql, params) {
  return db.transaction(async (tx) => {
    await tx.exec(uid ? "set local role authenticated" : "set local role anon");
    if (uid) await tx.query("select set_config('request.jwt.claim.sub', $1, true)", [uid]);
    return (await tx.query(sql, params)).rows;
  });
}
// un joueur existant joue une partie Snake comme le site (ticket puis submit_score_v2)
const u = ids[0];
const run = (await as(u, "select public.game_start('snake') r"))[0].r;
await db.exec(`update public.game_runs set started_at = now() - interval '60 seconds' where id = '${run}'`);
const r = (await as(u, "select public.submit_score_v2('snake', 42, $1) r", [run]))[0].r;
console.log("partie enregistrée :", JSON.stringify(r));
assert.equal(Number((await db.query("select count(*) n from public.scores")).rows[0].n), 100);
// un nouvel inscrit
const nu = "eeeeeeee-0000-4000-8000-000000000001";
await db.exec(`insert into auth.users (id) values ('${nu}')`);
await as(nu, "insert into public.profiles (id, pseudo, country) values ($1, 'nouveau', 'FR')", [nu]).catch(async (e) => { console.log("création profil directe :", e.message); });
console.log("me() :", JSON.stringify((await as(u, "select public.me() m"))[0].m).slice(0, 160));
const lb = await as(null, "select * from public.leaderboard('snake', null, 5)");
console.log("classement visiteur :", lb.length, "lignes");
assert.ok(lb.length > 0);
await assert.rejects(as(u, "select public.submit_score('snake', 100)"), /permission denied|does not exist/);
// relance refusée sans rien modifier
await assert.rejects(db.exec(big), /PRE-CONTROLE/);
console.log("relance refusée proprement ; OK");

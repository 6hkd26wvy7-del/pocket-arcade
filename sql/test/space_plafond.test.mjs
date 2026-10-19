// Non-régression du bug du 19/10 : un score Space Attack > 100 000 était tronqué à 100 000 par le site (plafond v17),
// donc le record restait bloqué. Vrai PostgreSQL 16 local en mémoire (PGlite), aucune base distante.
// Lancer : cd sql/test && npm install && node space_plafond.test.mjs
import assert from "node:assert/strict";
import fs from "node:fs";
import { fileURLToPath } from "node:url";
import { PGlite } from "@electric-sql/pglite";

const read = (rel) => fs.readFileSync(fileURLToPath(new URL(rel, import.meta.url)), "utf8");
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
await db.exec(read("../schema_all.sql"));
await db.exec(read("../schema_v25_plafond_space_v2.sql"));
await db.exec(read("../schema_v25_plafond_space_v2.sql"));   // relançable

let k = 0;
async function player() {
  k++;
  const id = "cccccccc-0000-4000-8000-" + String(k).padStart(12, "0");
  await db.exec(`insert into auth.users (id) values ('${id}'); insert into public.profiles (id, pseudo, country) values ('${id}', 'joueur_${k}', 'FR');
                 insert into public.player_stats (user_id) values ('${id}') on conflict do nothing;
                 insert into public.beta_members (user_id) values ('${id}') on conflict do nothing;`);
  return id;
}
async function as(uid, sql, params) {
  return db.transaction(async (tx) => {
    await tx.exec("set local role authenticated");
    await tx.query("select set_config('request.jwt.claim.sub', $1, true)", [uid]);
    return (await tx.query(sql, params)).rows;
  });
}
// Une partie de `secs` secondes (le ticket est antidaté) puis envoi du score, comme le fait le site.
async function play(uid, game, score, secs) {
  const run = (await as(uid, "select public.game_start($1) r", [game]))[0].r;
  await db.exec(`update public.game_runs set started_at = now() - interval '${secs} seconds' where id = '${run}'`);
  return (await as(uid, "select public.submit_score_v2($1,$2,$3) r", [game, score, run]))[0].r;
}
const best = async (uid, game) => (await db.query("select max(score)::int m from public.scores where user_id = $1 and game = $2", [uid, game])).rows[0].m;
const fails = (p, msg) => assert.rejects(p, (e) => e.message.includes(msg), "attendu : " + msg);
let n = 0; const t = async (name, fn) => { try { await fn(); } catch (e) { console.error("ECHEC -", name, "\n", e.message); process.exit(1); } n++; console.log("ok -", name); };

await t("plafonds : Space 5 000 000, Snake et Blocks inchangés", async () => {
  const r = (await db.query("select public.game_max_score('space') s, public.game_max_score('snake') n, public.game_max_score('blocks') b, public.game_max_score('autre') x")).rows[0];
  assert.deepEqual(r, { s: 5000000, n: 429, b: 50000, x: 0 });
});
await t("le bug : une partie à 200 000 en 2 minutes est enregistrée en entier, le record monte", async () => {
  const u = await player();
  await play(u, "space", 100000, 120);
  assert.equal(await best(u, "space"), 100000);
  await db.exec("update public.scores set created_at = now() - interval '1 minute'");   // passe l'anti-rafale de 8 s
  await play(u, "space", 213456, 150);
  assert.equal(await best(u, "space"), 213456);
});
await t("limite exacte : 100 001 était refusé (v17), accepté maintenant", async () => {
  const u = await player(); await play(u, "space", 100001, 60); assert.equal(await best(u, "space"), 100001);
});
await t("le plafond absolu existe toujours : 5 000 001 refusé, 5 000 000 accepté", async () => {
  const u = await player();
  await fails(play(u, "space", 5000001, 2000), "invalid score");
  const v = await player(); await play(v, "space", 5000000, 2000); assert.equal(await best(v, "space"), 5000000);
});
await t("l'anti-triche par durée est intact : 200 000 en 10 s refusé, ticket à usage unique", async () => {
  const u = await player();
  await fails(play(u, "space", 200000, 10), "implausible score");
  const run = (await as(u, "select public.game_start('space') r"))[0].r;
  await db.exec(`update public.game_runs set started_at = now() - interval '120 seconds' where id = '${run}'`);
  await as(u, "select public.submit_score_v2('space', 150000, $1)", [run]);
  await fails(as(u, "select public.submit_score_v2('space', 150000, $1)", [run]), "invalid run");
});
await t("pas de score sans ticket : l'envoi direct reste fermé aux joueurs", async () => {
  const u = await player();
  await assert.rejects(as(u, "select public.submit_score('space', 150000)"), /permission denied/);
  await assert.rejects(as(u, "insert into public.scores (user_id, game, score) values ($1, 'space', 999999)", [u]), /permission denied|row-level security/);
});
await t("récompenses non gonflées : un score de 2 000 000 donne au plus 60 XP de score et 26 BOYCOINS", async () => {
  const u = await player(); const r = await play(u, "space", 2000000, 1000);
  assert.ok(r.xp <= 65, "xp " + r.xp); assert.ok(r.bc <= 26, "bc " + r.bc);
});
await t("le site n'envoie plus de score tronqué : même constante que la base, aucune troncature à 100 000", async () => {
  const html = read("../../src/app-fragment.html");
  const cap = Number(/var SPACE_SCORE_MAX = (\d+);/.exec(html)[1]);
  assert.equal(cap, (await db.query("select public.game_max_score('space')::int c")).rows[0].c, "constante du site = plafond de la base");
  assert.ok(!/Math\.min\([^)]*,\s*100000\)/.test(html), "plus de Math.min(..., 100000)");
  const uses = html.match(/Math\.min\([^)]*SPACE_SCORE_MAX\)/g) || [];
  assert.equal(uses.length, 2, "envoi classé + partie continuée");
});

console.log(n + " tests OK");

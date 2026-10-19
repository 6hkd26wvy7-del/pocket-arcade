// Tests de la migration v24 (invitations de jeu entre amis) sur un vrai PostgreSQL 16 local en mémoire (PGlite).
// Aucune base distante. Installation : cd sql/test && npm install   puis   node invitations.test.mjs
import assert from "node:assert/strict";
import fs from "node:fs";
import { fileURLToPath } from "node:url";
import { PGlite } from "@electric-sql/pglite";

const SQL = (f) => fs.readFileSync(fileURLToPath(new URL("../" + f, import.meta.url)), "utf8");
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
await db.exec(SQL("schema_all.sql"));
await db.exec(SQL("schema_v24_invitations_jeu.sql"));
await db.exec(SQL("schema_v24_invitations_jeu.sql"));   // relançable

const id = (n) => "bbbbbbbb-0000-4000-8000-" + String(n).padStart(12, "0");
const [A, B, C, D, F1, F2, F3, F4, F5, F6] = [1, 2, 3, 4, 11, 12, 13, 14, 15, 16].map(id);
const names = { [A]: "ana_t", [B]: "ben_t", [C]: "cleo_t", [D]: "dan_t", [F1]: "fan1", [F2]: "fan2", [F3]: "fan3", [F4]: "fan4", [F5]: "fan5", [F6]: "fan6" };
for (const [u, p] of Object.entries(names)) {
  await db.exec(`insert into auth.users (id) values ('${u}'); insert into public.profiles (id, pseudo, country) values ('${u}', '${p}', 'FR');
                 insert into public.player_stats (user_id) values ('${u}') on conflict do nothing;`);
}
const friend = (x, y) => db.exec(`insert into public.friendships (user_a, user_b, requested_by, status)
  values (least('${x}'::uuid, '${y}'::uuid), greatest('${x}'::uuid, '${y}'::uuid), '${x}', 'accepted') on conflict do nothing`);
for (const u of [B, C, F1, F2, F3, F4, F5, F6]) await friend(A, u);   // D n'est l'ami de personne

// Exécute une requête comme un joueur connecté (rôle authenticated) ou un visiteur (uid = null → anon).
async function as(uid, sql, params) {
  return db.transaction(async (tx) => {
    await tx.exec("set local role " + (uid ? "authenticated" : "anon"));
    await tx.query("select set_config('request.jwt.claim.sub', $1, true)", [uid || ""]);
    return (await tx.query(sql, params)).rows;
  });
}
const send = (uid, pseudo, game = "snake", mode = "live") => as(uid, "select public.send_game_invite($1,$2,$3) r", [pseudo, game, mode]).then((r) => r[0].r);
const respond = (uid, inv, ok) => as(uid, "select public.respond_game_invite($1,$2) r", [inv, ok]).then((r) => r[0].r);
const mine = (uid) => as(uid, "select public.my_game_invites() r").then((r) => r[0].r);
const fails = async (p, msg) => assert.rejects(p, (e) => e.message.includes(msg), "attendu : " + msg);
const reset = () => db.exec("delete from public.game_invites; delete from public.notifications;");
const SQLRAW = (q) => db.exec(q);

let n = 0;
const t = async (name, fn) => {
  await reset();
  try { await fn(); } catch (e) { console.error("ECHEC -", name, "\n", e.message, "\n", String(e.stack).split("\n").filter((l) => l.includes("invitations.test")).join("\n")); process.exit(1); }
  n++; console.log("ok -", name);
};

await t("seul un ami peut inviter (inconnu, soi-même, non-ami, bloqué)", async () => {
  await fails(send(A, "dan_t"), "not friends");
  await fails(send(D, "ana_t"), "not friends");
  await fails(send(A, "personne"), "unknown player");
  await fails(send(A, "ana_t"), "cannot invite yourself");
  await fails(send(A, "ben_t", "pong"), "invalid game");
  await fails(send(A, "ben_t", "snake", "x"), "invalid game");
  await as(C, "select public.block_user('ana_t')");
  await fails(send(A, "cleo_t"), "blocked");
  await db.exec("delete from public.blocks"); await friend(A, C);   // block_user retire aussi l'amitié
});

await t("invitation live : le destinataire la voit, sans code avant d'avoir accepté", async () => {
  const r = await send(A, "ben_t", "snake");
  assert.equal(r.mode, "live");
  const b = await mine(B); assert.equal(b.incoming.length, 1);
  assert.equal(b.incoming[0].from, "ana_t"); assert.equal(b.incoming[0].game, "snake"); assert.equal(b.incoming[0].room_code, null);
  const a = await mine(A); assert.equal(a.outgoing[0].to, "ben_t"); assert.equal(a.outgoing[0].room_code, null);
  assert.deepEqual((await mine(C)).incoming, []);
  const notif = await as(B, "select kind, body from public.my_notifications()"); assert.equal(notif[0].kind, "game_invite"); assert.equal(notif[0].body, "ana_t");
});

await t("accepter donne la même salle aux deux joueurs (lettre selon le jeu)", async () => {
  for (const [game, letter] of [["snake", "S"], ["space", "P"], ["boyblocks", "X"]]) {
    await reset();
    const inv = await send(A, "ben_t", game);
    const res = await respond(B, inv.id, true);
    assert.equal(res.status, "accepted"); assert.match(res.room_code, new RegExp("^" + letter + "[ABCDEFGHJKMNPQRSTUVWXYZ2-9]{5}$"));
    assert.equal((await mine(A)).outgoing[0].room_code, res.room_code);
    assert.equal((await mine(B)).incoming[0].room_code, res.room_code);
    assert.equal((await as(A, "select kind from public.my_notifications()"))[0].kind, "game_invite_accept");
  }
});

await t("seul le destinataire répond ; l'expéditeur et un tiers n'ont aucun accès", async () => {
  const inv = await send(A, "ben_t");
  await fails(respond(A, inv.id, true), "invite not found");
  await fails(respond(C, inv.id, true), "invite not found");
  await fails(respond(D, inv.id, false), "invite not found");
  assert.equal((await respond(B, inv.id, true)).status, "accepted");
  await fails(respond(B, inv.id, false), "invite closed");
});

await t("refus : silencieux pour l'expéditeur, pause de 10 minutes avant de réinviter", async () => {
  const inv = await send(A, "ben_t");
  assert.equal((await respond(B, inv.id, false)).status, "declined");
  assert.equal((await as(A, "select count(*)::int c from public.my_notifications() where kind like 'game_invite%'"))[0].c, 0);
  assert.equal((await mine(A)).outgoing[0].status, "declined");
  await fails(send(A, "ben_t"), "declined recently");
  await SQLRAW("update public.game_invites set responded_at = now() - interval '11 minutes'");
  await send(A, "ben_t");
});

await t("anti-doublon : une seule invitation en attente par paire (dans les deux sens)", async () => {
  await send(A, "ben_t");
  await fails(send(A, "ben_t", "space"), "already pending");
  await fails(send(B, "ana_t"), "already pending");
});

await t("anti-spam : 5 en attente, 20 par heure, 6 par ami et par heure", async () => {
  for (const p of ["ben_t", "cleo_t", "fan1", "fan2", "fan3"]) await send(A, p);
  await fails(send(A, "fan4"), "too many pending");
  await reset();
  await SQLRAW(`insert into public.game_invites (from_id, to_id, game, mode, room_code, status, created_at, expires_at)
    select '${A}', '${F5}', 'snake', 'live', 'SAAAAA', 'cancelled', now() - interval '5 minutes', now() from generate_series(1, 20)`);
  await fails(send(A, "ben_t"), "too fast");
  await reset();
  await SQLRAW(`insert into public.game_invites (from_id, to_id, game, mode, room_code, status, created_at, expires_at)
    select '${A}', '${B}', 'snake', 'live', 'SAAAAA', 'cancelled', now() - interval '5 minutes', now() from generate_series(1, 6)`);
  await fails(send(A, "ben_t"), "too many for this friend");
  await send(A, "cleo_t");   // les autres amis ne sont pas touchés
});

await t("expiration : live 2 min, async 48 h, plus rien ne s'accepte après", async () => {
  const live = await send(A, "ben_t", "snake", "live");
  const dur = (await db.query(`select extract(epoch from (expires_at - created_at))::int s from public.game_invites where id = '${live.id}'`)).rows[0].s;
  assert.ok(dur >= 119 && dur <= 121, "live = 2 min");
  await SQLRAW("update public.game_invites set expires_at = now() - interval '1 second'");
  await fails(respond(B, live.id, true), "invite closed");
  assert.deepEqual((await mine(B)).incoming, []);   // la lecture suivante enregistre l'expiration (un appel qui échoue annule ses écritures)
  assert.equal((await db.query("select status from public.game_invites")).rows[0].status, "expired");
  await reset();
  const as1 = await send(A, "ben_t", "snake", "async");
  assert.equal((await db.query(`select extract(epoch from (expires_at - created_at))::int s from public.game_invites where id = '${as1.id}'`)).rows[0].s, 48 * 3600);
});

await t("la fenêtre pour rejoindre la salle se ferme 5 minutes après l'acceptation", async () => {
  const inv = await send(A, "ben_t");
  const res = await respond(B, inv.id, true);
  assert.equal((await mine(A)).outgoing[0].room_code, res.room_code);
  await SQLRAW("update public.game_invites set expires_at = now() - interval '1 second'");
  assert.equal((await mine(A)).outgoing.find((o) => o.room_code) , undefined);
  assert.deepEqual((await mine(B)).incoming, []);
});

await t("annulation : seul l'expéditeur, et plus de réponse possible ensuite", async () => {
  const inv = await send(A, "ben_t");
  await fails(as(B, "select public.cancel_game_invite($1)", [inv.id]), "invite not found");
  await fails(as(C, "select public.cancel_game_invite($1)", [inv.id]), "invite not found");
  await as(A, "select public.cancel_game_invite($1)", [inv.id]);
  await fails(respond(B, inv.id, true), "invite closed");
  await fails(as(A, "select public.cancel_game_invite($1)", [inv.id]), "invite not found");
  await send(A, "ben_t");   // on peut réinviter
});

await t("défi asynchrone : score à battre, chacun une seule fois, résultat des deux", async () => {
  const inv = await send(A, "ben_t", "boyblocks", "async");
  await fails(as(B, "select public.invite_report_score($1, 50)", [inv.id]), "invite closed");   // pas avant d'avoir accepté
  await fails(as(C, "select public.invite_report_score($1, 50)", [inv.id]), "invite not found");
  assert.equal((await as(A, "select public.invite_report_score($1, 120) r", [inv.id]))[0].r.status, "pending");
  await fails(as(A, "select public.invite_report_score($1, 130)", [inv.id]), "invite closed");
  const acc = await respond(B, inv.id, true); assert.equal(acc.from_score, 120); assert.equal(acc.room_code, null);
  await fails(as(B, "select public.invite_report_score($1, -1)", [inv.id]), "invalid score");
  await fails(as(B, "select public.invite_report_score($1, 99999999)", [inv.id]), "invalid score");
  const done = (await as(B, "select public.invite_report_score($1, 80) r", [inv.id]))[0].r;
  assert.deepEqual(done, { status: "done", from_score: 120, to_score: 80 });
  await fails(as(B, "select public.invite_report_score($1, 200)", [inv.id]), "invite closed");
  assert.equal((await as(A, "select kind from public.my_notifications()"))[0].kind, "game_invite_done");
  assert.equal((await mine(A)).outgoing[0].status, "done");
});

await t("fin d'amitié ou blocage entre l'invitation et la réponse : invitation annulée", async () => {
  const inv = await send(A, "ben_t");
  await db.exec(`delete from public.friendships where user_a = least('${A}'::uuid,'${B}'::uuid) and user_b = greatest('${A}'::uuid,'${B}'::uuid)`);
  assert.deepEqual(await respond(B, inv.id, true), { status: "cancelled" });
  assert.equal((await db.query("select status from public.game_invites")).rows[0].status, "cancelled");
  await friend(A, B);
});

await t("la table est fermée : aucun accès direct, aucun visiteur anonyme", async () => {
  await send(A, "ben_t");
  await assert.rejects(as(A, "select * from public.game_invites"), /permission denied/);
  await assert.rejects(as(B, "update public.game_invites set status = 'accepted'"), /permission denied/);
  await assert.rejects(as(null, "select public.my_game_invites()"), /permission denied/);
  await assert.rejects(as(null, "select public.send_game_invite('ben_t','snake','live')"), /permission denied/);
  await assert.rejects(as(A, "select public.expire_game_invites()"), /permission denied/);
  await assert.rejects(as(A, "select public.invite_room_code('snake')"), /permission denied/);
});

await t("joueur banni : aucune invitation", async () => {
  await db.exec(`insert into public.bans (user_id, reason) values ('${A}', 'test') on conflict do nothing`);
  await fails(send(A, "ben_t"), "banned");
  await db.exec("delete from public.bans");
});

console.log(n + " tests OK");

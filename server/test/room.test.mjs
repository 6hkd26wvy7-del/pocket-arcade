import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { ArenaRoom, verifyJwt, resetJwksCache } from "../worker.js";

// ---- faux Cloudflare ----
class End {
  constructor() { this.l = {}; this.peer = null; this.closed = false; this.sent = []; }
  addEventListener(ev, fn) { (this.l[ev] = this.l[ev] || []).push(fn); }
  accept() {}
  send(data) { if (this.closed) throw new Error("closed"); setTimeout(() => this.peer.emit("message", { data }), 0); }
  emit(ev, arg) { (this.l[ev] || []).forEach((f) => f(arg)); }
  close(code) { if (this.closed) return; this.closed = true; this.code = code; setTimeout(() => { this.emit("close", {}); this.peer.closed = true; this.peer.emit("close", {}); }, 0); }
}
globalThis.WebSocketPair = class { constructor() { const a = new End(), b = new End(); a.peer = b; b.peer = a; this[0] = a; this[1] = b; } };
globalThis.Response = class { constructor(body, init = {}) { this.body = body; this.status = init.status; this.webSocket = init.webSocket; } };

const URL_ = "https://test.supabase.co";
const kp = await webcrypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
const jwk = { ...(await webcrypto.subtle.exportKey("jwk", kp.publicKey)), kid: "k1", alg: "ES256" };
const b64 = (o) => Buffer.from(typeof o === "string" ? o : JSON.stringify(o)).toString("base64url");
async function token(sub, over = {}, key = kp.privateKey) {
  const h = b64({ alg: "ES256", kid: "k1", typ: "JWT" });
  const p = b64({ sub, aud: "authenticated", iss: URL_ + "/auth/v1", exp: Math.floor(Date.now() / 1000) + 3600, ...over });
  const sig = Buffer.from(await webcrypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, Buffer.from(h + "." + p))).toString("base64url");
  return h + "." + p + "." + sig;
}
const U1 = "11111111-1111-1111-1111-111111111111", U2 = "22222222-2222-2222-2222-222222222222", U3 = "33333333-3333-3333-3333-333333333333", U4 = "44444444-4444-4444-4444-444444444444";
const names = { [U1]: "Ana", [U2]: "Ben", [U3]: "Cat" }; // U4 : pas de profil
const FETCH = async (url) => {
  if (url.endsWith("/jwks.json")) return { ok: true, json: async () => ({ keys: [jwk] }) };
  const id = url.match(/id=eq\.([0-9a-f-]+)/)[1];
  return { ok: true, json: async () => (names[id] ? [{ pseudo: names[id] }] : []) };
};
const env = { SUPABASE_URL: URL_, SUPABASE_KEY: "pk", FETCH, TICK_MS: 4, COUNTDOWN_MS: 20, GRACE_MS: 60 };
let n = 0; const t = async (name, fn) => { await fn(); n++; console.log("ok -", name); };
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

// un faux téléphone
async function phone(room, tok) {
  const res = await room.fetch({ url: "https://x/play/SABCDE" });
  const ws = res.webSocket; const inbox = [];
  ws.addEventListener("message", (e) => inbox.push(JSON.parse(e.data)));
  ws.send = ((orig) => (d) => orig.call(ws, d))(ws.send);
  const out = { ws, inbox,
    say(o) { ws.peer.emit("message", { data: typeof o === "string" ? o : JSON.stringify(o) }); },
    async hello(tk) { out.say({ t: "hello", token: tk }); await wait(30); },
    last(type) { return [...inbox].reverse().find((m) => m.t === type); },
    has(type) { return inbox.some((m) => m.t === type); } };
  // on lit côté "client" : les messages du serveur arrivent sur ws (client), on envoie via le serveur peer
  return out;
}
// NB: ws = bout "client" ; ses messages entrants viennent du serveur. Pour parler AU serveur on émet sur ws.peer.

await t("jeton valide accepté, mauvais jetons refusés", async () => {
  resetJwksCache();
  const ok = await verifyJwt(await token(U1), env, FETCH);
  assert.equal(ok.uid, U1);
  await assert.rejects(verifyJwt(await token(U1, { exp: 10 }), env, FETCH), /expired/);
  await assert.rejects(verifyJwt(await token(U1, { iss: "https://evil/auth/v1" }), env, FETCH), /issuer/);
  await assert.rejects(verifyJwt(await token(U1, { aud: "anon" }), env, FETCH), /audience/);
  await assert.rejects(verifyJwt(await token("not-a-uuid"), env, FETCH), /subject/);
  const other = await webcrypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  await assert.rejects(verifyJwt(await token(U1, {}, other.privateKey), env, FETCH), /signature/);
  const good = await token(U1); const parts = good.split(".");
  await assert.rejects(verifyJwt(parts[0] + "." + b64({ sub: U2, aud: "authenticated", iss: URL_ + "/auth/v1", exp: 9999999999 }) + "." + parts[2], env, FETCH), /signature/);
  await assert.rejects(verifyJwt("abc", env, FETCH), /bad token/);
  await assert.rejects(verifyJwt("x".repeat(5000), env, FETCH), /bad token/);
  const none = b64({ alg: "none" }) + "." + b64({ sub: U1 }) + ".";
  await assert.rejects(verifyJwt(none, env, FETCH), /unsupported/);
});

await t("sans hello valide, la salle refuse (jeton faux, pas de profil)", async () => {
  const room = new ArenaRoom({}, env);
  const a = await phone(room); await a.hello("garbage");
  assert.equal(a.last("error").code, "auth"); assert.ok(a.ws.peer.closed);
  const b = await phone(room); await b.hello(await token(U4));
  assert.equal(b.last("error").code, "auth"); // jeton valide mais aucun profil
});

await t("deux joueurs: salon, compte à rebours, partie complète, fin valide", async () => {
  const room = new ArenaRoom({}, env);
  const a = await phone(room), b = await phone(room);
  await a.hello(await token(U1));
  assert.equal(a.last("lobby").players[0], "Ana"); assert.equal(a.last("lobby").you, 0);
  await b.hello(await token(U2));
  assert.equal(b.last("lobby").you, 1); assert.deepEqual(b.last("lobby").players, ["Ana", "Ben"]);
  await wait(60);
  assert.ok(a.has("countdown") && b.has("countdown"));
  assert.ok(a.has("state"));
  // spam + messages bizarres : ne doivent rien casser
  for (let i = 0; i < 200; i++) a.say({ t: "dir", d: "U" });
  a.say("pas du json"); a.say({ t: "dir", d: "ZZZ" }); a.say({ t: "hello" }); a.say("x".repeat(6000));
  await wait(1500);
  const end = a.last("state");
  assert.equal(end.over, true); assert.ok([0, 1, "draw"].includes(end.winner));
  assert.equal(JSON.stringify(a.last("state")), JSON.stringify(b.last("state"))); // même vérité pour les deux
});

await t("troisième joueur refusé, même compte qui revient reprend sa place", async () => {
  const room = new ArenaRoom({}, { ...env, COUNTDOWN_MS: 5000 });
  const a = await phone(room), b = await phone(room), c = await phone(room);
  await a.hello(await token(U1)); await b.hello(await token(U2)); await c.hello(await token(U3));
  assert.equal(c.last("error").code, "full");
  const a2 = await phone(room); await a2.hello(await token(U1));
  assert.equal(a2.last("lobby").you, 0); assert.ok(a.ws.peer.closed); // l'ancienne connexion est fermée
});

await t("déconnexion en cours de partie: l'autre gagne après le délai, retour possible avant", async () => {
  const room = new ArenaRoom({}, { ...env, TICK_MS: 50 });
  const a = await phone(room), b = await phone(room);
  await a.hello(await token(U1)); await b.hello(await token(U2));
  await wait(100);
  b.ws.peer.close(); await wait(20);              // Ben part
  const b2 = await phone(room); await b2.hello(await token(U2)); // et revient vite
  assert.equal(b2.last("lobby").you, 1); await wait(150);
  assert.notEqual(a.last("state").reason, "left");
  a.ws.peer.close(); await wait(200);              // Ana part pour de bon
  assert.equal(b2.last("state").over, true); assert.equal(b2.last("state").winner, 1); assert.equal(b2.last("state").reason, "left");
});

await t("un message dir avant le hello est ignoré", async () => {
  const room = new ArenaRoom({}, env);
  const a = await phone(room); a.say({ t: "dir", d: "U" }); await wait(20);
  assert.equal(a.inbox.length, 0);
});
console.log(n + " tests OK"); process.exit(0);

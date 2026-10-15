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
  if (url.includes("/rpc/arena_check")) return { ok: true, json: async () => true };
  if (url.endsWith("/jwks.json")) return { ok: true, json: async () => ({ keys: [jwk] }) };
  const id = url.match(/id=eq\.([0-9a-f-]+)/)[1];
  return { ok: true, json: async () => (names[id] ? [{ pseudo: names[id] }] : []) };
};
const env = { SUPABASE_URL: URL_, SUPABASE_KEY: "pk", FETCH, TICK_MS: 4, COUNTDOWN_MS: 20, GRACE_MS: 60 };
let n = 0; const t = async (name, fn) => { await fn(); n++; console.log("ok -", name); };
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

// un faux téléphone
async function phone(room, code) {
  const res = await room.fetch({ url: "https://x/play/" + code });
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


async function duo(code, extra = {}) {
  const room = new ArenaRoom({}, { ...env, ...extra });
  const a = await phone(room, code), b = await phone(room, code);
  await a.hello(await token(U1)); await b.hello(await token(U2));
  return { room, a, b };
}
await t("space co-op: salon, partie, messages move acceptes, fin d'equipe", async () => {
  const { a, b } = await duo("PTEST1", { TICK_MS: 5, DT_MS: 66 });
  assert.equal(a.last("lobby").kind, "space");
  await wait(80);
  for (let i = 0; i < 100; i++) { a.say({ t: "move", x: 20 }); b.say({ t: "move", x: 120 }); }
  b.say({ t: "move", x: "zzz" }); b.say({ t: "move", x: null }); b.say({ t: "dir", d: "U" });
  await wait(300);
  const mid = a.last("state"); assert.equal(mid.kind, "space"); assert.equal(mid.ships.length, 2); assert.ok(mid.ships[0].x < 40); assert.ok(mid.ships[1].x > 80);
  for (let i = 0; i < 400 && !a.last("state").over; i++) await wait(50);
  const end = a.last("state"); assert.equal(end.over, true); assert.equal(end.winner, "team");
  assert.equal(JSON.stringify(a.last("state")), JSON.stringify(b.last("state")));
});
await t("space co-op: un joueur part, l'autre continue", async () => {
  const { a, b } = await duo("PTEST2", { TICK_MS: 20, GRACE_MS: 40 });
  await wait(100); b.ws.peer.close(); await wait(150);
  assert.equal(a.last("state").ships[1].lives, 0); assert.equal(a.last("state").over, false);
});
await t("blocks duel: salon, actions, memes pieces, fin avec gagnant", async () => {
  const { a, b } = await duo("BTEST1", { TICK_MS: 5, DT_MS: 50 });
  assert.equal(a.last("lobby").kind, "blocks");
  await wait(80);
  a.say({ t: "act", d: "L" }); a.say({ t: "act", a: "ZZZ" }); a.say({ t: "act", a: "L" }); b.say({ t: "act", a: "HARD" });
  for (let i = 0; i < 120; i++) { a.say({ t: "act", a: "HARD" }); if (i % 3 === 0) b.say({ t: "act", a: "ROT" }); await wait(10); if (a.last("state") && a.last("state").over) break; }
  const end = a.last("state"); assert.equal(end.kind, "blocks"); assert.equal(end.over, true); assert.ok([0, 1, "draw"].includes(end.winner));
  assert.equal(JSON.stringify(a.last("state")), JSON.stringify(b.last("state")));
});
await t("blocks duel: abandon = l'autre gagne", async () => {
  const { a, b } = await duo("BTEST2", { TICK_MS: 20, GRACE_MS: 40 });
  await wait(100); b.ws.peer.close(); await wait(150);
  assert.equal(a.last("state").over, true); assert.equal(a.last("state").winner, 0); assert.equal(a.last("state").reason, "left");
});
await t("code sans lettre de jeu valide: refus au niveau du routeur", async () => {
  const { default: worker } = await import("../worker.js");
  const r = await worker.fetch({ url: "https://x/play/ZZZZZ", headers: { get: () => "websocket" } }, { ARENA: {} });
  assert.equal(r.status, 200); // simple page d'accueil, pas de salle
});
console.log(n + " tests OK"); process.exit(0);

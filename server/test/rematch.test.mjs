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


await t("revanche : les deux acceptent, une nouvelle partie démarre", async () => {
  resetJwksCache();
  const room = new ArenaRoom({}, { ...env, END_CLOSE_MS: 5000 });
  const a = await phone(room, null), b = await phone(room, null);
  await a.hello(await token(U1)); await b.hello(await token(U2));
  await wait(120);
  assert.ok(a.has("countdown") && b.has("countdown"));
  room.finish("timeout");
  await wait(30);
  assert.equal(room.phase, "over");
  a.inbox.length = 0; b.inbox.length = 0;
  a.say({ t: "again" }); await wait(30);
  assert.equal(room.phase, "over", "un seul joueur : pas de nouvelle partie");
  assert.ok(b.has("rematch"));
  b.say({ t: "again" }); await wait(80);
  assert.ok(a.has("countdown") && b.has("countdown"));
  await wait(60);
  assert.ok(a.inbox.some((m) => m.t === "state" && m.over === false), "la nouvelle partie envoie des états en cours");
  room.finish("timeout");
});

await t("revanche : si l'adversaire part, l'autre est prévenu et ne peut pas relancer", async () => {
  resetJwksCache();
  const room = new ArenaRoom({}, { ...env, END_CLOSE_MS: 5000 });
  const a = await phone(room, null), b = await phone(room, null);
  await a.hello(await token(U1)); await b.hello(await token(U2));
  await wait(120);
  room.finish("timeout"); await wait(30);
  a.inbox.length = 0;
  b.ws.peer.emit("close", {}); await wait(30);
  assert.ok(a.has("left"));
  a.say({ t: "again" }); await wait(40);
  assert.equal(room.phase, "over");
});
console.log(n + " tests OK");
process.exit(0);

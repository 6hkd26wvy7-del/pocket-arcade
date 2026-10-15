import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import { ArenaRoom, resetJwksCache } from "../worker.js";

class End {
  constructor() { this.l = {}; this.peer = null; this.closed = false; }
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
async function token(sub) {
  const h = b64({ alg: "ES256", kid: "k1", typ: "JWT" });
  const p = b64({ sub, aud: "authenticated", iss: URL_ + "/auth/v1", exp: Math.floor(Date.now() / 1000) + 3600 });
  const sig = Buffer.from(await webcrypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, kp.privateKey, Buffer.from(h + "." + p))).toString("base64url");
  return h + "." + p + "." + sig;
}
const U = "11111111-1111-1111-1111-111111111111";
let rpcMode = "ok", rpcCalls = [];
const FETCH = async (url, opts) => {
  if (url.endsWith("/jwks.json")) return { ok: true, json: async () => ({ keys: [jwk] }) };
  if (url.includes("/rpc/arena_check")) {
    rpcCalls.push(opts);
    if (rpcMode === "ok") return { ok: true, json: async () => true };
    if (rpcMode === "down") throw new Error("network");
    if (rpcMode === "garbage") return { ok: false, json: async () => { throw new Error("x"); } };
    return { ok: false, json: async () => ({ message: rpcMode }) };
  }
  return { ok: true, json: async () => [{ pseudo: "Ana" }] };
};
const env = { SUPABASE_URL: URL_, SUPABASE_KEY: "pk", FETCH, TICK_MS: 4, COUNTDOWN_MS: 20, GRACE_MS: 60 };
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
async function tryJoin(mode) {
  resetJwksCache(); rpcMode = mode; rpcCalls = [];
  const room = new ArenaRoom({ storage: {} }, env);
  const res = await room.fetch({ url: "https://x/play/SABCDE" });
  const ws = res.webSocket; const inbox = [];
  ws.addEventListener("message", (e) => inbox.push(JSON.parse(e.data)));
  ws.peer.emit("message", { data: JSON.stringify({ t: "hello", token: await token(U) }) });
  await wait(40);
  return { inbox, ws };
}
let n = 0; const t = async (name, fn) => { await fn(); n++; console.log("ok -", name); };

await t("joueur autorisé : accepté, jeton transmis à la base", async () => {
  const r = await tryJoin("ok");
  assert.ok(r.inbox.some((m) => m.t === "joined" || m.t === "state" || m.t === "lobby" || m.t === "hello" || m.t === "welcome" || !m.error), JSON.stringify(r.inbox));
  assert.ok(!r.inbox.some((m) => m.t === "error"), JSON.stringify(r.inbox));
  assert.match(rpcCalls[0].headers.Authorization, /^Bearer /);
});
for (const [mode, code] of [["banned", "banned"], ["beta", "beta"], ["maintenance", "maintenance"]]) {
  await t("refusé : " + mode, async () => {
    const r = await tryJoin(mode);
    const e = r.inbox.find((m) => m.t === "error");
    assert.equal(e && e.code, code);
    assert.equal(r.ws.peer.code, 4004);
  });
}
await t("base injoignable : refus (fail closed)", async () => {
  const r = await tryJoin("down");
  assert.equal((r.inbox.find((m) => m.t === "error") || {}).code, "auth");
});
await t("réponse illisible : refus", async () => {
  const r = await tryJoin("garbage");
  assert.equal((r.inbox.find((m) => m.t === "error") || {}).code, "auth");
});
console.log(n + " tests OK"); process.exit(0);

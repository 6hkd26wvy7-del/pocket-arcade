import assert from "node:assert/strict";
import { webcrypto } from "node:crypto";
import * as SN from "../arena-engine.js";
import * as SP from "../space-engine.js";
import * as BBD from "../boyblocks-duel.js";
import * as BOT from "../boybot.js";
import { ArenaRoom } from "../worker.js";

let n = 0; const t = async (name, fn) => { await fn(); n++; console.log("ok -", name); };
const avg = (a) => a.reduce((x, y) => x + y, 0) / a.length;

// ---------- Snake ----------
function snakeMatch(seed, l0, l1) {
  const g = SN.newGame(seed), b = [BOT.makeBot("snake", l0, seed), BOT.makeBot("snake", l1, seed + 7)];
  while (!g.over) { b.forEach((x, i) => x.act(g, i).forEach((m) => SN.setDirection(g, i, m.d))); SN.step(g); }
  return g;
}
await t("snake: les parties de BOYBOT finissent, il mange des pommes", () => {
  const sc = [];
  for (let s = 1; s <= 60; s++) { const g = snakeMatch(s, "normal", "normal"); assert.ok(g.over); sc.push(g.players[0].score + g.players[1].score); }
  assert.ok(avg(sc) > 6, "pommes mangées en moyenne : " + avg(sc));
});
await t("snake: Difficile bat Facile la plupart du temps, sans etre invincible", () => {
  let hard = 0, easy = 0;
  for (let s = 1; s <= 80; s++) { const g = snakeMatch(s, s % 2 ? "hard" : "easy", s % 2 ? "easy" : "hard"); const hi = s % 2 ? 0 : 1; if (g.winner === hi) hard++; else if (g.winner === 1 - hi) easy++; }
  assert.ok(hard > easy * 1.5, "difficile " + hard + " / facile " + easy);
});
await t("snake: un seul ordre a la fois, jamais de demi-tour", () => {
  const g = SN.newGame(3), b = BOT.makeBot("snake", "hard", 3);
  for (let k = 0; k < 300 && !g.over; k++) { const ms = b.act(g, 0); assert.ok(ms.length <= 1); ms.forEach((m) => assert.notEqual(m.d, { U: "D", D: "U", L: "R", R: "L" }[g.players[0].dir])); ms.forEach((m) => SN.setDirection(g, 0, m.d)); SN.step(g); }
});

// ---------- BoyBlocks ----------
function blocksSolo(seed, level, size = 8) {
  const g = BBD.newGame(seed, size), b = BOT.makeBot("boyblocks", level, seed); let refused = 0;
  while (!g.over) { for (const m of b.act(g, 1, 250)) if (!BBD.input(g, 1, m)) refused++; BBD.step(g, 250); if (g.players[1].over) break; }
  return { score: g.players[1].score, moves: g.players[1].moves, refused };
}
await t("boyblocks: tous les coups de BOYBOT sont acceptes par le serveur (8x8 et 9x9)", () => {
  for (let s = 1; s <= 12; s++) { const r = blocksSolo(s, ["easy", "normal", "hard"][s % 3], s % 2 ? 8 : 9); assert.equal(r.refused, 0); assert.ok(r.moves > 5); }
});
await t("boyblocks: rythme humain (Facile lent, Difficile plus rapide) et Difficile marque plus", () => {
  const e = [], h = [], em = [], hm = [];
  for (let s = 1; s <= 12; s++) { const a = blocksSolo(s, "easy"), b = blocksSolo(s, "hard"); e.push(a.score); h.push(b.score); em.push(a.moves); hm.push(b.moves); }
  assert.ok(avg(hm) > avg(em) * 1.5 && avg(hm) < 200, "coups " + avg(em) + " / " + avg(hm));
  assert.ok(avg(h) > avg(e), "scores " + avg(e) + " / " + avg(h));
});

// ---------- Space Attack ----------
function spaceCoop(seed, level) {
  const g = SP.newGame(seed), b = [BOT.makeBot("space", level, seed), BOT.makeBot("space", level, seed + 1)]; let k = 0, picked = 0;
  while (!g.over && k++ < 40000) { b.forEach((x, i) => x.act(g, i, SP.TICK_MS).forEach((m) => SP.setTarget(g, i, m.x))); SP.step(g); g.ships.forEach((s) => { if (s.picked && s.pickedAt === g.t) picked++; }); }
  return { wave: g.wave, picked };
}
await t("space: BOYBOT attaque, avance dans les vagues et ramasse des bonus", () => {
  const w = [], p = [];
  for (let s = 1; s <= 20; s++) { const r = spaceCoop(s, "normal"); w.push(r.wave); p.push(r.picked); }
  assert.ok(avg(w) >= 2.5, "vague moyenne " + avg(w)); assert.ok(p.reduce((a, b) => a + b) > 0, "aucun bonus ramassé");
});
await t("space: Difficile va plus loin que Facile", () => {
  const e = [], h = [];
  for (let s = 1; s <= 20; s++) { e.push(spaceCoop(s, "easy").wave); h.push(spaceCoop(s, "hard").wave); }
  assert.ok(avg(h) > avg(e), avg(e) + " / " + avg(h));
});

// ---------- Salle de jeu ----------
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
const b64 = (o) => Buffer.from(JSON.stringify(o)).toString("base64url");
async function token(sub) {
  const h = b64({ alg: "ES256", kid: "k1", typ: "JWT" }), p = b64({ sub, aud: "authenticated", iss: URL_ + "/auth/v1", exp: Math.floor(Date.now() / 1000) + 3600 });
  const sig = Buffer.from(await webcrypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, kp.privateKey, Buffer.from(h + "." + p))).toString("base64url");
  return h + "." + p + "." + sig;
}
const U1 = "11111111-1111-1111-1111-111111111111", U2 = "22222222-2222-2222-2222-222222222222";
const FETCH = async (url) => {
  if (url.includes("/rpc/arena_check")) return { ok: true, json: async () => true };
  if (url.endsWith("/jwks.json")) return { ok: true, json: async () => ({ keys: [jwk] }) };
  return { ok: true, json: async () => [{ pseudo: url.includes(U1) ? "Ana" : "Ben" }] };
};
const env = { SUPABASE_URL: URL_, SUPABASE_KEY: "pk", FETCH, TICK_MS: 4, COUNTDOWN_MS: 20, GRACE_MS: 60, END_CLOSE_MS: 2000 };
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
async function phone(room, code, uid, bot) {
  const res = await room.fetch({ url: "https://x/play/" + code }); const ws = res.webSocket, inbox = [];
  ws.addEventListener("message", (e) => inbox.push(JSON.parse(e.data)));
  const say = (o) => ws.peer.emit("message", { data: JSON.stringify(o) });
  say(bot === undefined ? { t: "hello", token: await token(uid) } : { t: "hello", token: await token(uid), bot }); await wait(40);
  return { ws, inbox, say, last: (ty) => [...inbox].reverse().find((m) => m.t === ty) };
}
await t("salle: un seul joueur + BOYBOT, partie lancee, BOYBOT signale comme bot et joue", async () => {
  const room = new ArenaRoom({}, { ...env, DT_MS: 140 });
  const a = await phone(room, "SBOT1", U1, "normal");
  const lob = a.last("lobby"); assert.deepEqual(lob.bots, [false, true]); assert.equal(lob.players[1], BOT.BOT_NAME);
  await wait(200);
  const st = a.last("state"); assert.ok(st, "la partie a démarré"); assert.equal(st.kind, "snake");
  for (let i = 0; i < 100 && !a.last("state").over; i++) await wait(10);
  assert.ok(a.inbox.filter((m) => m.t === "state").length > 5);
});
await t("salle: BOYBOT en Space co-op et en BoyBlocks", async () => {
  const r1 = new ArenaRoom({}, { ...env, DT_MS: 66 }); const a = await phone(r1, "PBOT1", U1, "hard"); await wait(300);
  const xs = a.inbox.filter((m) => m.t === "state").map((m) => m.ships[1].x); assert.ok(new Set(xs).size > 2, "le vaisseau de BOYBOT bouge");
  const r2 = new ArenaRoom({}, { ...env, TICK_MS: 2, DT_MS: 2000 }); const b = await phone(r2, "XBOT1", U1, "hard"); await wait(300);
  assert.ok(b.last("state").players[1].moves > 0, "BOYBOT a posé des pièces");
});
await t("salle: revanche avec BOYBOT, salle pleine pour un autre, difficulte inconnue refusee", async () => {
  const room = new ArenaRoom({}, { ...env, DT_MS: 140 });
  const a = await phone(room, "SBOT2", U1, "easy");
  const other = await phone(room, "SBOT2", U2); assert.equal(other.last("error").code, "full");
  for (let i = 0; i < 300 && !(a.last("state") && a.last("state").over); i++) await wait(10);
  a.say({ t: "again" }); await wait(80);
  assert.ok(a.inbox.filter((m) => m.t === "countdown").length >= 2, "nouvelle partie lancée");
  const r2 = new ArenaRoom({}, env); const z = await phone(r2, "SBOT3", U1, "expert"); assert.equal(z.last("error").code, "bot");
});
console.log(n + " tests OK"); process.exit(0);

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
  const res = await room.fetch({ url: "https://x/play/XABCDE" });
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
import * as BB from "../boyblocks-engine.js";
import * as D from "../boyblocks-duel.js";
import fs from "node:fs";

function firstMove(g) {
  for (let s = 0; s < 3; s++) { if (!g.pieces[s]) continue; const sh = BB.PIECES[g.pieces[s].p];
    for (let r = 0; r <= 8 - sh.h; r++) for (let c = 0; c <= 8 - sh.w; c++) if (BB.fits(g.grid, sh, r, c)) return { t: "place", slot: s, r, c }; }
  return null;
}
async function start(opts = {}) {
  resetJwksCache();
  const room = new ArenaRoom({}, { ...env, END_CLOSE_MS: 5000, ...opts });
  const a = await phone(room, null), b = await phone(room, null);
  await a.hello(await token(U1)); await b.hello(await token(U2));
  await wait(120);
  return { room, a, b };
}

await t("le moteur du serveur est identique à celui du téléphone", () => {
  if (!fs.existsSync(new URL("../../shared/boyblocks-engine.js", import.meta.url))) return;   // dépôt de déploiement : pas de dossier shared
  assert.equal(fs.readFileSync(new URL("../boyblocks-engine.js", import.meta.url), "utf8"), fs.readFileSync(new URL("../../shared/boyblocks-engine.js", import.meta.url), "utf8"));
});

await t("duel : mêmes pièces, mêmes grilles de départ pour les deux joueurs", () => {
  const g = D.newGame(777);
  assert.deepEqual(g.players[0].pieces, g.players[1].pieces);
  assert.deepEqual(D.snapshot(g).players[0].grid, "0".repeat(64));
});

await t("duel : un coup valide marque des points, les deux écrans le voient tout de suite", async () => {
  const { room, a, b } = await start();
  assert.equal(room.phase, "playing");
  const st = a.last("state");
  assert.equal(st.kind, "boyblocks"); assert.ok(st.seed >= 0);
  const mirror = BB.newGame(st.seed, { ensureFit: false });
  const mv = firstMove(mirror); BB.place(mirror, mv.slot, mv.r, mv.c);
  b.ws.peer.emit("message", { data: JSON.stringify(mv) });         // le joueur 2 joue
  await wait(20);
  const s2 = a.last("state");
  assert.equal(s2.players[1].score, mirror.score, "le score vient du serveur");
  assert.equal(s2.players[1].moves, 1);
  assert.equal(s2.players[0].score, 0);
  assert.equal(b.last("state").players[1].grid, mirror.grid.join(""));
  room.finish("timeout");
});

await t("duel : coups illégaux ignorés (hors grille, case occupée, mauvaise pièce, types invalides)", async () => {
  const { room, a, b } = await start();
  const say = (o) => a.ws.peer.emit("message", { data: JSON.stringify(o) });
  say({ t: "place", slot: 0, r: 99, c: 0 }); say({ t: "place", slot: 7, r: 0, c: 0 }); say({ t: "place", slot: 0, r: 0.5, c: 0 });
  say({ t: "place", slot: "0", r: 0, c: 0 }); say({ t: "place", slot: 0, r: null, c: 0 }); say({ t: "autre" });
  await wait(30);
  assert.equal(room.game.players[0].moves, 0);
  assert.equal(room.game.players[0].score, 0);
  room.finish("timeout");
});

await t("duel : cadence humaine (pas de rafale de coups parfaits)", async () => {
  const g = D.newGame(5); let ok = 0;
  for (let i = 0; i < 30; i++) { const m = firstMove(g.players[0]); if (!m) break; if (D.input(g, 0, m)) ok++; }
  assert.ok(ok <= 5, "au plus 4-5 coups instantanés, a eu " + ok);
  g.ms = 60000; // plus tard dans la partie, la cadence normale passe
  const m = firstMove(g.players[0]); assert.ok(D.input(g, 0, m));
});

await t("duel : à la fin du temps, le plus haut score gagne", () => {
  const g = D.newGame(9);
  g.ms = 5000; D.input(g, 0, firstMove(g.players[0]));
  assert.ok(g.players[0].score > g.players[1].score);
  D.step(g, 200000);
  assert.equal(g.over, true); assert.equal(g.reason, "time"); assert.equal(g.winner, 0);
  const h = D.newGame(9); D.step(h, 200000); assert.equal(h.winner, "draw");
});

await t("duel : un joueur bloqué qui est derrière perd tout de suite, s'il est devant l'autre continue", () => {
  const g = D.newGame(3); g.ms = 100000;
  g.players[0].score = 10; g.players[0].over = true; g.players[1].score = 50;
  D.step(g, 10); assert.equal(g.over, true); assert.equal(g.winner, 1);
  const h = D.newGame(3); h.ms = 100000;
  h.players[0].score = 90; h.players[0].over = true; h.players[1].score = 50;
  D.step(h, 10); assert.equal(h.over, false, "l'autre peut encore le dépasser");
  h.players[1].over = true; D.step(h, 10); assert.equal(h.over, true); assert.equal(h.winner, 0);
});

await t("duel : resynchronisation (sync) renvoie la liste de mes coups, pas ceux de l'adversaire", async () => {
  const { room, a, b } = await start();
  const st = a.last("state"); const mirror = BB.newGame(st.seed, { ensureFit: false });
  const mv = firstMove(mirror); BB.place(mirror, mv.slot, mv.r, mv.c);
  a.ws.peer.emit("message", { data: JSON.stringify(mv) }); await wait(20);
  a.inbox.length = 0; b.inbox.length = 0;
  a.ws.peer.emit("message", { data: JSON.stringify({ t: "sync" }) }); await wait(20);
  const s = a.last("sync"); assert.deepEqual(s.log, [[mv.slot, mv.r, mv.c]]); assert.equal(s.seed, st.seed);
  assert.ok(!b.has("sync"));
  room.finish("timeout");
});

await t("duel : partie complète jouée par deux robots, résultat identique à une simulation locale", async () => {
  const { room, a, b } = await start({ DT_MS: 2000, TICK_MS: 2 });
  const st = a.last("state"); const mirrors = [BB.newGame(st.seed, { ensureFit: false }), BB.newGame(st.seed, { ensureFit: false })];
  for (let k = 0; k < 400 && !room.game.over; k++) {
    for (const [i, ph] of [[0, a], [1, b]]) {
      const mv = firstMove(mirrors[i]); if (!mv) continue;
      ph.ws.peer.emit("message", { data: JSON.stringify(mv) });
      await wait(2);
      if (room.game.players[i].moves > mirrors[i].moves) BB.place(mirrors[i], mv.slot, mv.r, mv.c);
    }
  }
  await wait(40);
  assert.equal(room.game.over, true);
  const fin = a.last("state");
  assert.equal(fin.players[0].score, mirrors[0].score);
  assert.equal(fin.players[1].score, mirrors[1].score);
  assert.ok(["draw", 0, 1].includes(fin.winner));
});
console.log(n + " tests OK");
process.exit(0);

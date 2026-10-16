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
  let n2 = 0, h2 = 0;
  for (let s = 1; s <= 120; s++) { const g = snakeMatch(s * 7 + 3, "normal", "hard"); if (g.winner === 1) h2++; else if (g.winner === 0) n2++; }
  assert.ok(h2 > n2, "difficile " + h2 + " / normal " + n2);
});
await t("snake: un seul ordre a la fois, jamais de demi-tour", () => {
  const g = SN.newGame(3), b = BOT.makeBot("snake", "hard", 3);
  for (let k = 0; k < 300 && !g.over; k++) { const ms = b.act(g, 0); assert.ok(ms.length <= 1); ms.forEach((m) => assert.notEqual(m.d, { U: "D", D: "U", L: "R", R: "L" }[g.players[0].dir])); ms.forEach((m) => SN.setDirection(g, 0, m.d)); SN.step(g); }
});

await t("snake: BOYBOT part dans les memes conditions qu'un humain (miroir, longueur, score, vitesse)", () => {
  for (let s = 1; s <= 20; s++) {
    const g = SN.newGame(s), [h, b] = g.players;
    assert.equal(h.body.length, b.body.length); assert.equal(h.score, 0); assert.equal(b.score, 0);
    assert.equal(h.body[0].y, b.body[0].y); assert.equal(h.body[0].x, SN.COLS - 1 - b.body[0].x);   // positions en miroir
    assert.equal(h.dir, "R"); assert.equal(b.dir, "L");
    const before = b.body.map((c) => ({ ...c })); SN.step(g);                                          // une case par tour, comme l'humain
    assert.equal(Math.abs(b.body[0].x - before[0].x) + Math.abs(b.body[0].y - before[0].y), 1);
  }
});
// Pommes placées dans des situations précises : le bot (place 1) doit la manger, sans tourner autour.
function scenario(level, food, body, dir, limit) {
  const g = SN.newGame(1); g.players[0].alive = false; g.players[0].body = [{ x: -9, y: -9 }];
  const me = g.players[1]; me.body = body.map(([x, y]) => ({ x, y })); me.dir = dir; g.food = [food];
  const bot = BOT.makeBot("snake", level, 5); let k = 0;
  while (k++ < limit) {
    bot.act(g, 1).forEach((m) => SN.setDirection(g, 1, m.d)); SN.step(g); g.over = false;
    if (!me.alive) return { dead: true, k };
    if (me.score > 0) return { ate: true, k };
  }
  return { k };
}
const SITUATIONS = {
  "pomme dans un coin": [{ x: 0, y: 0 }, [[12, 12], [13, 12], [14, 12]], "L"],
  "pomme contre un mur": [{ x: 23, y: 7 }, [[5, 20], [4, 20], [3, 20]], "R"],
  "pomme juste derrière lui (demi-tour impossible)": [{ x: 15, y: 10 }, [[12, 10], [13, 10], [14, 10]], "L"],
  "pomme derrière son long corps": [{ x: 10, y: 9 }, [[10, 11], [11, 11], [12, 11], [13, 11], [13, 10], [12, 10], [11, 10], [10, 10], [9, 10], [8, 10], [7, 10], [6, 10]], "D"],
  "pomme dans un cul-de-sac en U": [{ x: 1, y: 1 }, [[6, 6], [6, 7], [6, 8]], "U"],
};
for (const level of BOT.LEVELS) {
  await t("snake " + level + ": mange la pomme dans 5 situations, sans boucle ni accident", () => {
    for (const [name, [food, body, dir]] of Object.entries(SITUATIONS)) {
      const r = scenario(level, food, body, dir, 160);
      assert.ok(r.ate, name + " : " + JSON.stringify(r));
    }
  });
}
await t("snake: pomme inaccessible = mode survie (il ne se jette pas contre un mur)", () => {
  for (const level of BOT.LEVELS) {
    const g = SN.newGame(1); g.players[0].alive = false; g.players[0].body = [{ x: -9, y: -9 }];
    const wall = []; for (let y = 0; y < SN.ROWS; y++) wall.push({ x: 18, y });   // un mur infranchissable (le serpent adverse « mort » n'en est pas un : on le simule)
    g.players[0].alive = true; g.players[0].body = wall; g.players[0].dir = "D"; g.players[0].queue = [];
    const me = g.players[1]; me.body = [{ x: 8, y: 12 }, { x: 9, y: 12 }, { x: 10, y: 12 }]; me.dir = "L"; g.food = [{ x: 21, y: 3 }];
    const bot = BOT.makeBot("snake", level, 3); let k = 0;
    for (; k < 150; k++) { bot.act(g, 1).forEach((m) => SN.setDirection(g, 1, m.d)); g.players[0].body = wall; g.players[0].alive = true; SN.step(g); g.players[0].body = wall; g.players[0].alive = true; g.over = false; if (!me.alive) break; }
    assert.ok(k >= 150 || level === "easy" && k > 60, level + " a survécu " + k + " tours");
  }
});
await t("snake: plus de tours en rond (Facile mange regulierement)", () => {
  const rate = {};
  for (const level of BOT.LEVELS) {
    let eat = 0, ticks = 0, starve = 0;
    for (let s = 1; s <= 30; s++) {
      const g = SN.newGame(s), b = BOT.makeBot("snake", level, s); g.players[0].alive = false; g.players[0].body = [{ x: -9, y: -9 }];
      let since = 0;
      for (let k = 0; k < 500; k++) { b.act(g, 1).forEach((m) => SN.setDirection(g, 1, m.d)); const sc = g.players[1].score; SN.step(g); g.over = false; if (!g.players[1].alive) break; ticks++; if (g.players[1].score > sc) { eat++; since = 0; } else if (++since > 80) { starve++; since = 0; } }
    }
    rate[level] = 100 * eat / ticks; assert.ok(starve <= 3, level + " : " + starve + " longues périodes sans manger");
  }
  assert.ok(rate.easy > 4 && rate.easy < rate.normal && rate.normal <= rate.hard + 0.5, JSON.stringify(rate));
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
await t("pause contre BOYBOT : tout s'arrete, reprise apres le compte a rebours, au meme tour", async () => {
  const room = new ArenaRoom({}, { ...env, TICK_MS: 10, DT_MS: 140, RESUME_MS: 60 });
  const a = await phone(room, "SBOTP", U1, "normal");
  await wait(120);
  a.say({ t: "pause" }); await wait(30);
  assert.ok(a.last("paused"), "pause confirmée");
  const tick0 = a.last("state").tick, n0 = a.inbox.length;
  await wait(200);
  assert.equal(a.inbox.filter((m, i) => i >= n0 && m.t === "state").length, 0, "aucun tour pendant la pause");
  const g = room.game; assert.equal(g.tick, tick0, "le serveur n'avance plus");
  const bot = g.players[1].body.map((c) => c.x + "," + c.y).join(" ");
  a.say({ t: "dir", d: "U" }); await wait(20); assert.equal(g.players[0].queue.length, 0, "pas d'ordre pendant la pause");
  a.say({ t: "resume" }); await wait(20);
  assert.equal(a.last("resume").ms, 60);
  a.say({ t: "dir", d: "U" }); await wait(10); assert.deepEqual(g.players[0].queue, ["U"], "direction choisie pendant le compte à rebours");
  assert.equal(g.tick, tick0); assert.equal(g.players[1].body.map((c) => c.x + "," + c.y).join(" "), bot, "BOYBOT figé pendant le compte à rebours");
  await wait(120);
  assert.ok(g.tick > tick0, "la partie a repris"); assert.equal(room.phase === "playing" || room.phase === "over", true);
  assert.ok(a.inbox.filter((m) => m.t === "state" && m.tick === tick0 + 1).length >= 1, "reprise au tour suivant, sans saut");
});
await t("pause refusee entre deux humains (regles des duels inchangees)", async () => {
  const room = new ArenaRoom({}, { ...env, TICK_MS: 10, DT_MS: 140 });
  const a = await phone(room, "SHUM1", U1), b = await phone(room, "SHUM1", U2);
  await wait(40); a.say({ t: "dir", d: "U" }); b.say({ t: "dir", d: "D" });   // pas de face-à-face
  await wait(40); const t0 = room.game.tick;
  a.say({ t: "pause" }); await wait(60);
  assert.equal(a.last("paused"), undefined); assert.ok(room.game.tick > t0, "la partie continue"); assert.notEqual(room.phase, "paused");
});
console.log(n + " tests OK"); process.exit(0);

// Space Attack en coopération (2 vaisseaux contre les mêmes envahisseurs).
// Le serveur décide de tout. Chaque joueur envoie seulement où il veut aller (targetX).

import { rng } from "./arena-engine.js";

export const W = 144, H = 208, HUD = 16, SHIP_W = 12, SHIP_H = 8, SHIP_Y = H - 16, EW = 10, EH = 8, COLS = 6;
export const BW = 8, BH = 8, MAX_LIVES = 5;
export const TICK_MS = 33;
// Bonus identiques au solo (durées, fréquences, effets). En coopération, un bonus profite au vaisseau qui le ramasse.
export const BONUS = {
  triple: { ms: 10000, weight: 30 },   // trois tirs en éventail
  rapid:  { ms: 9000,  weight: 30 },   // cadence doublée
  laser:  { ms: 5000,  weight: 15 },   // rayon perçant, plus large
  shield: { ms: 15000, weight: 15 },   // absorbe un tir ennemi
  life:   { ms: 0,     weight: 10 },   // +1 vie (5 au maximum, sinon +250 points)
};
const BONUS_KEYS = Object.keys(BONUS), BONUS_TOTAL = BONUS_KEYS.reduce((t, k) => t + BONUS[k].weight, 0);
const POWERS = ["triple", "rapid", "laser", "shield"];
function pickBonus(rand) {
  let x = rand() * BONUS_TOTAL;
  for (const k of BONUS_KEYS) { x -= BONUS[k].weight; if (x < 0) return k; }
  return BONUS_KEYS[0];
}
export function applyBonus(g, s, kind) {
  if (kind === "life") { if (s.lives < MAX_LIVES) s.lives++; else g.score += 250; }
  else s.power[kind] = BONUS[kind].ms;          // reprendre un bonus actif relance sa durée (pas de cumul)
  s.picked = kind; s.pickedAt = g.t;
}
export const MAX_TICKS = Math.round(10 * 60 * 1000 / TICK_MS); // 10 minutes au plus

export function wave(n) {
  const rows = Math.min(2 + Math.floor((n - 1) / 2), 5), list = [];
  for (let r = 0; r < rows; r++) for (let c = 0; c < COLS; c++) list.push({ x: 10 + c * 16, y: HUD + 10 + r * 14, row: r });
  return list;
}

export function newGame(seed) {
  return {
    rand: rng(seed), tick: 0, t: 0, over: false, winner: null, reason: "",
    ships: [
      { x: W / 4 - SHIP_W / 2, target: null, lives: 3, invuln: 0, power: { triple: 0, rapid: 0, laser: 0, shield: 0 }, picked: null, pickedAt: 0 },
      { x: (3 * W) / 4 - SHIP_W / 2, target: null, lives: 3, invuln: 0, power: { triple: 0, rapid: 0, laser: 0, shield: 0 }, picked: null, pickedAt: 0 },
    ],
    bullets: [], shots: [], drops: [], enemies: wave(1), dir: 1, wave: 1, score: 0, fireAt: [0, 160], enemyFireAt: 1500,
  };
}

// Un joueur dit où il veut aller (0 à 144). Les valeurs absurdes sont ignorées.
export function setTarget(g, i, x) {
  const s = g.ships[i];
  if (!s || s.lives <= 0 || g.over) return false;
  if (typeof x !== "number" || !isFinite(x)) return false;
  s.target = Math.max(0, Math.min(W, x));
  return true;
}

function hit(a, b) { return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y; }

export function step(g, dtMs = TICK_MS) {
  if (g.over) return g;
  const dt = dtMs / 1000;
  g.tick++;
  g.t += dtMs;

  g.ships.forEach((s, i) => {
    if (s.lives <= 0) return;
    if (s.invuln > 0) s.invuln = Math.max(0, s.invuln - dtMs);
    POWERS.forEach((k) => { if (s.power[k] > 0) s.power[k] = Math.max(0, s.power[k] - dtMs); });
    if (s.target !== null) {
      const want = Math.max(0, Math.min(W - SHIP_W, s.target - SHIP_W / 2));
      const maxMove = 150 * dt, d = want - s.x;
      s.x += Math.abs(d) <= maxMove ? d : d > 0 ? maxMove : -maxMove;
    }
    // tir automatique, comme en solo (rapide : cadence doublée ; triple : éventail ; laser : rayon perçant)
    if (g.t >= g.fireAt[i]) {
      const cx = s.x + SHIP_W / 2 - 1;
      if (s.power.laser > 0) g.bullets.push({ x: cx - 1, y: SHIP_Y - 10, vx: 0, w: 4, h: 10, pierce: true });
      else g.bullets.push({ x: cx, y: SHIP_Y - 4, vx: 0, w: 2, h: 5 });
      if (s.power.triple > 0) {
        g.bullets.push({ x: cx - 3, y: SHIP_Y - 2, vx: -45, w: 2, h: 5 });
        g.bullets.push({ x: cx + 3, y: SHIP_Y - 2, vx: 45, w: 2, h: 5 });
      }
      g.fireAt[i] = g.t + (s.power.rapid > 0 ? 160 : 320);
    }
  });
  g.bullets.forEach((b) => { b.y -= 190 * dt; b.x += (b.vx || 0) * dt; });
  g.bullets = g.bullets.filter((b) => b.y > HUD - 10 && b.x > -4 && b.x < W + 4);

  const speed = 14 + g.wave * 5 + (COLS * 5 - g.enemies.length) * 0.4;
  let edge = false;
  g.enemies.forEach((e) => { e.x += g.dir * speed * dt; if (e.x < 2 || e.x + EW > W - 2) edge = true; });
  if (edge) { g.dir = -g.dir; g.enemies.forEach((e) => { e.x += g.dir * 2; e.y += 6; }); }

  if (g.enemies.length && g.t >= g.enemyFireAt) {
    const sh = g.enemies[Math.floor(g.rand() * g.enemies.length)];
    g.shots.push({ x: sh.x + EW / 2 - 1, y: sh.y + EH });
    g.enemyFireAt = g.t + Math.max(450, 1300 - g.wave * 80);
  }
  g.shots.forEach((s) => { s.y += (70 + g.wave * 6) * dt; });
  g.shots = g.shots.filter((s) => s.y < H);

  g.bullets = g.bullets.filter((b) => {
    const bb = { x: b.x, y: b.y, w: b.w || 2, h: b.h || 5 };
    let keep = true;
    for (let i = g.enemies.length - 1; i >= 0; i--) {
      const e = g.enemies[i];
      if (hit(bb, { x: e.x, y: e.y, w: EW, h: EH })) {
        g.enemies.splice(i, 1); g.score += 10 + (4 - Math.min(e.row, 4)) * 2;
        if (!b.pierce) { keep = false; break; }
      }
    }
    return keep;
  });

  // bonus qui tombent : ramassés par le premier vaisseau (vivant) qui les touche, perdus s'ils sortent de l'écran
  g.drops.forEach((o) => { o.y += 38 * dt; });
  g.drops = g.drops.filter((o) => {
    for (const s of g.ships) {
      if (s.lives <= 0) continue;
      if (hit({ x: o.x, y: o.y, w: BW, h: BH }, { x: s.x - 1, y: SHIP_Y - 2, w: SHIP_W + 2, h: SHIP_H + 4 })) { applyBonus(g, s, o.kind); return false; }
    }
    return o.y < H;
  });

  g.ships.forEach((s) => {
    if (s.lives <= 0 || s.invuln > 0) return;
    const box = { x: s.x, y: SHIP_Y, w: SHIP_W, h: SHIP_H };
    for (let k = 0; k < g.shots.length; k++) {
      if (hit({ x: g.shots[k].x, y: g.shots[k].y, w: 2, h: 5 }, box)) {
        g.shots.splice(k, 1);
        if (s.power.shield > 0) { s.power.shield = 0; s.invuln = 600; break; }   // le bouclier absorbe un tir
        s.lives--; s.invuln = 1500; break;
      }
    }
  });

  if (g.ships.every((s) => s.lives <= 0)) { g.over = true; g.winner = "team"; g.reason = "dead"; return g; }
  if (g.enemies.some((e) => e.y + EH >= SHIP_Y)) { g.over = true; g.winner = "team"; g.reason = "invaded"; return g; }
  if (g.tick >= MAX_TICKS) { g.over = true; g.winner = "team"; g.reason = "time"; return g; }

  if (!g.enemies.length) {
    g.score += 100 * g.wave;
    if (g.wave >= 2) g.drops.push({ kind: pickBonus(g.rand), x: Math.round(8 + g.rand() * (W - 16 - BW)), y: HUD + 2 });
    g.wave++; g.enemies = wave(g.wave); g.shots = []; g.dir = 1; g.enemyFireAt = g.t + 1500; }
  return g;
}

export function snapshot(g) {
  const r = (n) => Math.round(n * 10) / 10;
  return {
    t: "state", kind: "space", tick: g.tick, over: g.over, winner: g.winner, reason: g.reason,
    score: g.score, wave: g.wave,
    ships: g.ships.map((s) => {
      const o = { x: r(s.x), lives: s.lives, invuln: s.invuln > 0 }, pw = {};
      POWERS.forEach((k) => { if (s.power[k] > 0) pw[k] = Math.round(s.power[k]); });
      if (Object.keys(pw).length) o.power = pw;
      if (s.picked && g.t - s.pickedAt < 1400) o.picked = s.picked;
      return o;
    }),
    bullets: g.bullets.map((b) => (b.pierce ? [r(b.x), r(b.y), 1] : [r(b.x), r(b.y)])),
    drops: g.drops.map((o) => [r(o.x), r(o.y), o.kind]),
    shots: g.shots.map((b) => [r(b.x), r(b.y)]),
    enemies: g.enemies.map((e) => [r(e.x), r(e.y), e.row]),
  };
}

// Space Attack en coopération (2 vaisseaux contre les mêmes envahisseurs).
// Le serveur décide de tout. Chaque joueur envoie seulement où il veut aller (targetX).

import { rng } from "./arena-engine.js";

export const W = 144, H = 208, HUD = 16, SHIP_W = 12, SHIP_H = 8, SHIP_Y = H - 16, EW = 10, EH = 8, COLS = 6;
export const TICK_MS = 33;
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
      { x: W / 4 - SHIP_W / 2, target: null, lives: 3, invuln: 0 },
      { x: (3 * W) / 4 - SHIP_W / 2, target: null, lives: 3, invuln: 0 },
    ],
    bullets: [], shots: [], enemies: wave(1), dir: 1, wave: 1, score: 0, fireAt: [0, 160], enemyFireAt: 1500,
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
    if (s.target !== null) {
      const want = Math.max(0, Math.min(W - SHIP_W, s.target - SHIP_W / 2));
      const maxMove = 150 * dt, d = want - s.x;
      s.x += Math.abs(d) <= maxMove ? d : d > 0 ? maxMove : -maxMove;
    }
    if (g.t >= g.fireAt[i]) { g.bullets.push({ x: s.x + SHIP_W / 2 - 1, y: SHIP_Y - 4 }); g.fireAt[i] = g.t + 320; }
  });
  g.bullets.forEach((b) => { b.y -= 190 * dt; });
  g.bullets = g.bullets.filter((b) => b.y > HUD - 4);

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
    const bb = { x: b.x, y: b.y, w: 2, h: 5 };
    for (let i = 0; i < g.enemies.length; i++) {
      const e = g.enemies[i];
      if (hit(bb, { x: e.x, y: e.y, w: EW, h: EH })) { g.enemies.splice(i, 1); g.score += 10 + (4 - Math.min(e.row, 4)) * 2; return false; }
    }
    return true;
  });

  g.ships.forEach((s) => {
    if (s.lives <= 0 || s.invuln > 0) return;
    const box = { x: s.x, y: SHIP_Y, w: SHIP_W, h: SHIP_H };
    for (let k = 0; k < g.shots.length; k++) {
      if (hit({ x: g.shots[k].x, y: g.shots[k].y, w: 2, h: 5 }, box)) { g.shots.splice(k, 1); s.lives--; s.invuln = 1500; break; }
    }
  });

  if (g.ships.every((s) => s.lives <= 0)) { g.over = true; g.winner = "team"; g.reason = "dead"; return g; }
  if (g.enemies.some((e) => e.y + EH >= SHIP_Y)) { g.over = true; g.winner = "team"; g.reason = "invaded"; return g; }
  if (g.tick >= MAX_TICKS) { g.over = true; g.winner = "team"; g.reason = "time"; return g; }

  if (!g.enemies.length) { g.score += 100 * g.wave; g.wave++; g.enemies = wave(g.wave); g.shots = []; g.dir = 1; g.enemyFireAt = g.t + 1500; }
  return g;
}

export function snapshot(g) {
  const r = (n) => Math.round(n * 10) / 10;
  return {
    t: "state", kind: "space", tick: g.tick, over: g.over, winner: g.winner, reason: g.reason,
    score: g.score, wave: g.wave,
    ships: g.ships.map((s) => ({ x: r(s.x), lives: s.lives, invuln: s.invuln > 0 })),
    bullets: g.bullets.map((b) => [r(b.x), r(b.y)]),
    shots: g.shots.map((b) => [r(b.x), r(b.y)]),
    enemies: g.enemies.map((e) => [r(e.x), r(e.y), e.row]),
  };
}

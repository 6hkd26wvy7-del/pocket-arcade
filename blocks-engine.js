// Block Puzzle en duel (2 grilles). Les deux joueurs reçoivent les mêmes pièces, dans le même ordre.
// Quand tu complètes des lignes, ton adversaire reçoit des lignes « cadeau » (avec un trou) qui montent du bas.
// Le dernier encore en vie gagne. Le serveur décide de tout.

import { rng } from "./arena-engine.js";

export const COLS = 10, ROWS = 18;
export const TICK_MS = 50;
export const MAX_MS = 5 * 60 * 1000;
export const PIECES = [
  [[1, 1, 1, 1]], [[1, 1], [1, 1]], [[0, 1, 0], [1, 1, 1]], [[0, 1, 1], [1, 1, 0]],
  [[1, 1, 0], [0, 1, 1]], [[1, 0, 0], [1, 1, 1]], [[0, 0, 1], [1, 1, 1]],
];

export function rotate(m) {
  const h = m.length, w = m[0].length, r = [];
  for (let x = 0; x < w; x++) { r[x] = []; for (let y = h - 1; y >= 0; y--) r[x].push(m[y][x]); }
  return r;
}
export const newGrid = () => Array.from({ length: ROWS }, () => new Array(COLS).fill(0));
export function fits(grid, m, px, py) {
  for (let y = 0; y < m.length; y++) for (let x = 0; x < m[y].length; x++) {
    if (!m[y][x]) continue;
    const gx = px + x, gy = py + y;
    if (gx < 0 || gx >= COLS || gy >= ROWS) return false;
    if (gy >= 0 && grid[gy][gx]) return false;
  }
  return true;
}
function lock(grid, m, px, py) {
  for (let y = 0; y < m.length; y++) for (let x = 0; x < m[y].length; x++) if (m[y][x] && py + y >= 0) grid[py + y][px + x] = 1;
}
export function clearLines(grid) {
  let n = 0;
  for (let y = ROWS - 1; y >= 0; y--) {
    if (grid[y].every(Boolean)) { grid.splice(y, 1); grid.unshift(new Array(COLS).fill(0)); n++; y++; }
  }
  return n;
}
export const lineScore = (n, level) => [0, 100, 300, 500, 800][n] * level;
export const levelFor = (lines) => 1 + Math.floor(lines / 10);
export const gravityMs = (level) => Math.max(90, 700 - (level - 1) * 60);
export const garbageFor = (n) => [0, 0, 1, 2, 4][n];

function makeBag(rand) {
  const a = [0, 1, 2, 3, 4, 5, 6];
  for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(rand() * (i + 1)); [a[i], a[j]] = [a[j], a[i]]; }
  return a;
}

export function newGame(seed) {
  const pieceRand = rng(seed), holeRand = rng(seed ^ 0x9e3779b9);
  const g = { t: 0, over: false, winner: null, reason: "", pieceRand, holeRand, queue: [], players: [] };
  for (let i = 0; i < 2; i++) {
    g.players.push({ grid: newGrid(), cur: null, x: 0, y: 0, idx: 0, score: 0, lines: 0, level: 1, acc: 0, pending: 0, alive: true });
  }
  // la même suite de pièces pour les deux joueurs
  while (g.queue.length < 400) g.queue.push(...makeBag(pieceRand));
  g.players.forEach((p) => spawn(g, p));
  return g;
}

function pieceAt(g, p, n) { return PIECES[g.queue[p.idx + n]]; }

function spawn(g, p) {
  p.cur = pieceAt(g, p, 0);
  p.idx++;
  p.x = Math.floor((COLS - p.cur[0].length) / 2);
  p.y = 0;
  if (!fits(p.grid, p.cur, p.x, p.y)) p.alive = false;
}

// Les actions d'un joueur : L, R, ROT, SOFT, HARD
export function act(g, i, a) {
  const p = g.players[i];
  if (!p || !p.alive || g.over) return false;
  if (a === "L") { if (fits(p.grid, p.cur, p.x - 1, p.y)) { p.x--; return true; } return false; }
  if (a === "R") { if (fits(p.grid, p.cur, p.x + 1, p.y)) { p.x++; return true; } return false; }
  if (a === "ROT") {
    const r = rotate(p.cur);
    for (const k of [0, -1, 1, -2, 2]) if (fits(p.grid, r, p.x + k, p.y)) { p.cur = r; p.x += k; return true; }
    return false;
  }
  if (a === "SOFT") { if (drop(g, i)) p.score += 1; p.acc = 0; return true; }
  if (a === "HARD") {
    let c = 0;
    while (fits(p.grid, p.cur, p.x, p.y + 1)) { p.y++; c++; }
    p.score += c * 2;
    drop(g, i);
    p.acc = 0;
    return true;
  }
  return false;
}

// Fait descendre la pièce d'une case ; renvoie true si elle a pu descendre.
function drop(g, i) {
  const p = g.players[i], o = g.players[1 - i];
  if (fits(p.grid, p.cur, p.x, p.y + 1)) { p.y++; return true; }
  lock(p.grid, p.cur, p.x, p.y);
  const n = clearLines(p.grid);
  if (n) {
    p.lines += n; p.score += lineScore(n, p.level); p.level = levelFor(p.lines);
    o.pending += garbageFor(n);
  } else if (p.pending > 0) {
    addGarbage(g, p); // les lignes cadeau arrivent seulement quand tu ne fais pas de ligne
  }
  if (p.alive) spawn(g, p);
  return false;
}

function addGarbage(g, p) {
  const k = Math.min(p.pending, 6);
  p.pending = 0;
  for (let n = 0; n < k; n++) {
    const topRow = p.grid.shift();
    if (topRow.some(Boolean)) p.alive = false; // la pile est déjà tout en haut
    const hole = Math.floor(g.holeRand() * COLS);
    p.grid.push(Array.from({ length: COLS }, (_, x) => (x === hole ? 0 : 1)));
  }
}

export function step(g, dtMs = TICK_MS) {
  if (g.over) return g;
  g.t += dtMs;
  g.players.forEach((p, i) => {
    if (!p.alive) return;
    p.acc += dtMs;
    const gm = gravityMs(p.level);
    while (p.acc >= gm && p.alive) { p.acc -= gm; drop(g, i); }
  });
  const alive = g.players.map((p) => p.alive);
  if (!alive[0] && !alive[1]) {
    g.over = true; g.reason = "double";
    const a = g.players[0].score, b = g.players[1].score;
    g.winner = a === b ? "draw" : a > b ? 0 : 1;
  } else if (!alive[0] || !alive[1]) {
    g.over = true; g.winner = alive[0] ? 0 : 1; g.reason = "topout";
  } else if (g.t >= MAX_MS) {
    g.over = true; g.reason = "time";
    const a = g.players[0].score, b = g.players[1].score;
    g.winner = a === b ? "draw" : a > b ? 0 : 1;
  }
  return g;
}

export function snapshot(g) {
  return {
    t: "state", kind: "blocks", over: g.over, winner: g.winner, reason: g.reason,
    players: g.players.map((p, i) => {
      // la pièce en cours est incluse dans la grille envoyée (2 = pièce qui tombe)
      const grid = p.grid.map((row) => row.slice());
      if (p.alive && p.cur) for (let y = 0; y < p.cur.length; y++) for (let x = 0; x < p.cur[y].length; x++) {
        if (p.cur[y][x] && p.y + y >= 0 && p.y + y < ROWS) grid[p.y + y][p.x + x] = 2;
      }
      return { grid: grid.map((r) => r.join("")), score: p.score, lines: p.lines, level: p.level, pending: p.pending, alive: p.alive,
               next: pieceAt(g, p, 0) };
    }),
  };
}

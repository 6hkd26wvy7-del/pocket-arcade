// BOYBOT 🤖 : joueur virtuel des salles en ligne (bêta).
// Il ne triche pas : il lit la partie comme un téléphone la verrait et renvoie les MÊMES ordres qu'un humain
// ({t:"dir"}, {t:"move"}, {t:"place"}), qui passent par la même validation du serveur.
// Il n'est pas parfait exprès : temps de réaction, erreurs et imprécision selon la difficulté.
import * as BB from "./boyblocks-engine.js";
import { rng } from "./arena-engine.js";

export const LEVELS = ["easy", "normal", "hard"];
export const BOT_NAME = "BOYBOT 🤖";
export const BOT_UID = "boybot";

// Réglages par difficulté.
const CFG = {
  snake: {
    easy:   { every: 2, flood: false, headOn: false, noise: 4, blunder: 0.02 },   // regarde un pas sur deux, se piège parfois
    normal: { every: 1, flood: true,  headOn: false, noise: 2, blunder: 0.006 },
    hard:   { every: 1, flood: true,  headOn: true,  noise: 0.5, blunder: 0.001 },
  },
  boyblocks: {
    easy:   { think: [2200, 3800], top: 6, wild: 0.25 },   // lent, choisit souvent un coup moyen
    normal: { think: [1100, 1900], top: 2, wild: 0.06 },
    hard:   { think: [700, 1300],  top: 1, wild: 0.0 },
  },
  space: {
    easy:   { every: 350, dodge: 0.35, chase: 0.5, aim: 14 },
    normal: { every: 180, dodge: 0.75, chase: 0.85, aim: 6 },
    hard:   { every: 90,  dodge: 0.95, chase: 1.0, aim: 2 },
  },
};

export function makeBot(game, level, seed) {
  const lv = LEVELS.includes(level) ? level : "normal";
  const rand = rng((seed >>> 0) ^ 0x5eed);
  if (game === "snake") return snakeBot(CFG.snake[lv], rand);
  if (game === "boyblocks") return blocksBot(CFG.boyblocks[lv], rand);
  if (game === "space") return spaceBot(CFG.space[lv], rand);
  return null;
}

/* ---------------- Snake ---------------- */
const DIRS = { U: [0, -1], D: [0, 1], L: [-1, 0], R: [1, 0] };
const OPP = { U: "D", D: "U", L: "R", R: "L" };
const COLS = 24, ROWS = 24;

function snakeBot(cfg, rand) {
  let n = 0;
  return {
    // appelé à chaque tour, AVANT que le serveur fasse avancer la partie
    act(g, i) {
      const me = g.players[i], other = g.players[1 - i];
      if (!me || !me.alive || g.over || me.queue.length) return [];
      if (++n % cfg.every !== 0 && !deadAhead(g, me, me.dir)) return [];
      const blocked = new Set();
      g.players.forEach((p) => { if (!p.alive) return; p.body.forEach((c, k) => { if (k < p.body.length - 1) blocked.add(c.x + "," + c.y); }); });
      const head = me.body[0];
      let best = null, bestScore = -Infinity;
      for (const d of Object.keys(DIRS)) {
        if (d === OPP[me.dir]) continue;
        const x = head.x + DIRS[d][0], y = head.y + DIRS[d][1];
        let s;
        const wall = x < 0 || y < 0 || x >= COLS || y >= ROWS || blocked.has(x + "," + y);
        if (wall && rand() >= cfg.blunder) s = -1000;            // obstacle vu (sauf distraction rare)
        else if (wall) s = 0;
        else {
          s = -2 * foodDist(g, x, y);
          if (cfg.flood) { const room = flood(blocked, x, y, me.body.length * 2); if (room < me.body.length) s -= 400 - room; }
          if (cfg.headOn && other && other.alive) {
            const oh = other.body[0];
            if (Math.abs(oh.x - x) + Math.abs(oh.y - y) === 1) s -= 60;   // évite le face-à-face
          }
        }
        s += (rand() - 0.5) * cfg.noise * 2;
        if (s > bestScore) { bestScore = s; best = d; }
      }
      return best && best !== me.dir ? [{ t: "dir", d: best }] : [];
    },
  };
}
function deadAhead(g, me, d) {
  const h = me.body[0], x = h.x + DIRS[d][0], y = h.y + DIRS[d][1];
  if (x < 0 || y < 0 || x >= COLS || y >= ROWS) return true;
  return g.players.some((p) => p.alive && p.body.some((c, k) => k < p.body.length - 1 && c.x === x && c.y === y));
}
function foodDist(g, x, y) {
  let m = 99;
  for (const f of g.food) m = Math.min(m, Math.abs(f.x - x) + Math.abs(f.y - y));
  return m;
}
function flood(blocked, x, y, cap) {
  const seen = new Set([x + "," + y]), todo = [[x, y]];
  while (todo.length && seen.size < cap) {
    const [cx, cy] = todo.pop();
    for (const d of Object.values(DIRS)) {
      const nx = cx + d[0], ny = cy + d[1], k = nx + "," + ny;
      if (nx < 0 || ny < 0 || nx >= COLS || ny >= ROWS || blocked.has(k) || seen.has(k)) continue;
      seen.add(k); todo.push([nx, ny]);
    }
  }
  return seen.size;
}

/* ---------------- BoyBlocks ---------------- */
// Note d'une grille : pénalise les cases vides isolées, récompense les lignes presque pleines.
function gridQuality(grid, N) {
  let q = 0;
  for (let r = 0; r < N; r++) for (let c = 0; c < N; c++) {
    if (grid[r * N + c]) continue;
    let free = 0;
    if (r > 0 && !grid[(r - 1) * N + c]) free++;
    if (r < N - 1 && !grid[(r + 1) * N + c]) free++;
    if (c > 0 && !grid[r * N + c - 1]) free++;
    if (c < N - 1 && !grid[r * N + c + 1]) free++;
    if (free === 0) q -= 6; else if (free === 1) q -= 1.5;
  }
  for (let i = 0; i < N; i++) {
    let fr = 0, fc = 0;
    for (let j = 0; j < N; j++) { if (grid[i * N + j]) fr++; if (grid[j * N + i]) fc++; }
    q += (fr * fr + fc * fc) / (N * 4);
  }
  return q;
}
export function rankBlockMoves(p) {
  const N = p.size || 8, moves = [];
  p.pieces.forEach((pc, slot) => {
    if (!pc) return;
    const shape = BB.PIECES[pc.p];
    for (let r = 0; r <= N - shape.h; r++) for (let c = 0; c <= N - shape.w; c++) {
      if (!BB.fits(p.grid, shape, r, c)) continue;
      const sim = { ...p, grid: p.grid.slice(), pieces: p.pieces.slice(), log: [] };
      const res = BB.place(sim, slot, r, c);
      if (!res.ok) continue;
      // les pièces encore en main doivent rester posables
      const stuck = sim.pieces.some((x) => x && !BB.canPlaceAnywhere(sim.grid, BB.PIECES[x.p]));
      moves.push({ slot, r, c, v: res.gain * 1.2 + gridQuality(sim.grid, N) - (stuck ? 80 : 0) - (sim.over ? 200 : 0) });
    }
  });
  return moves.sort((a, b) => b.v - a.v);
}
function blocksBot(cfg, rand) {
  let wait = null;
  return {
    act(g, i, dt) {
      const p = g.players[i];
      if (!p || p.over || g.over) return [];
      if (wait === null) wait = cfg.think[0] + rand() * (cfg.think[1] - cfg.think[0]);
      wait -= dt;
      if (wait > 0) return [];
      wait = null;
      const moves = rankBlockMoves(p);
      if (!moves.length) return [];
      const pick = rand() < cfg.wild ? moves[Math.floor(rand() * Math.min(moves.length, 12))]
        : moves[Math.floor(rand() * Math.min(cfg.top, moves.length))];
      return [{ t: "place", slot: pick.slot, r: pick.r, c: pick.c }];
    },
  };
}

/* ---------------- Space Attack (coopération) ---------------- */
const SW = 144, SHIP_W = 12, SHIP_Y = 208 - 16;
function spaceBot(cfg, rand) {
  let since = 1e9, target = null, offset = 0;
  return {
    act(g, i, dt) {
      const s = g.ships[i];
      if (!s || s.lives <= 0 || g.over) return [];
      since += dt;
      if (since < cfg.every) return [];
      since = 0;
      const cx = s.x + SHIP_W / 2;
      // 1. un tir ennemi arrive sur moi ? on s'écarte (si on l'a vu)
      const threats = g.shots.filter((t) => t.y > SHIP_Y - 70 && t.y < SHIP_Y + 8 && t.x > s.x - 4 && t.x < s.x + SHIP_W + 4);
      if (threats.length && rand() < cfg.dodge) {
        const tx = threats[0].x, goRight = tx < cx ? true : tx > cx ? false : rand() < 0.5;
        let want = cx + (goRight ? 22 : -22);
        if (want < 8) want = cx + 22; else if (want > SW - 8) want = cx - 22;
        target = want;
      } else {
        // 2. un bonus tombe : on va le chercher
        const drop = (g.drops || []).filter((o) => o.y > 60).sort((a, b) => b.y - a.y)[0];
        if (drop && rand() < cfg.chase) target = drop.x + 4;
        else if (g.enemies.length) {
          // 3. sinon on vise l'ennemi le plus bas (le plus dangereux), avec une visée imparfaite
          if (rand() < 0.2) offset = (rand() - 0.5) * 2 * cfg.aim;
          const low = g.enemies.reduce((a, e) => (e.y > a.y ? e : a), g.enemies[0]);
          target = low.x + 5 + offset;
        }
      }
      if (target === null) return [];
      return [{ t: "move", x: Math.round(Math.max(0, Math.min(SW, target))) }];
    },
  };
}

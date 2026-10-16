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
export const CFG = {
  snake: {
    // lazy : parfois il tourne un tour en retard (réflexes plus lents) ; nearest : choisit la pomme la plus proche ;
    // flood : vérifie qu'il ne s'enferme pas ; headOn : évite le face-à-face ; blunder : rare inattention face à un obstacle.
    easy:   { lazy: 0.50, nearest: 0.4, flood: 0, headOn: false, race: false, blunder: 0.004 },
    normal: { lazy: 0.10, nearest: 0.85, flood: 1, headOn: false, race: false, blunder: 0.001 },
    hard:   { lazy: 0.0,  nearest: 1.0, flood: 3, headOn: true,  race: false, blunder: 0.0 },
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
// Recherche de chemin (parcours en largeur) vers une pomme choisie et GARDÉE jusqu'à ce qu'elle soit mangée :
// pas d'hésitation ni de tours autour de la pomme. Sans chemin : mode survie (case qui laisse le plus de place).
// Le niveau ne change que des défauts « humains » : réflexes plus lents, pomme moins bien choisie, pas d'anticipation.
const DIRS = { U: [0, -1], D: [0, 1], L: [-1, 0], R: [1, 0] };
const OPP = { U: "D", D: "U", L: "R", R: "L" };
const COLS = 24, ROWS = 24;
const key = (x, y) => y * COLS + x;
const inside = (x, y) => x >= 0 && y >= 0 && x < COLS && y < ROWS;

function snakeBot(cfg, rand) {
  let target = null;   // pomme visée {x, y}
  return {
    // appelé à chaque tour, AVANT que le serveur fasse avancer la partie
    act(g, i) {
      const me = g.players[i], other = g.players[1 - i];
      if (!me || !me.alive || g.over || me.queue.length) return [];
      // cases occupées au prochain tour (les queues avancent, sauf si le serpent mange : prudence, on les garde sauf la sienne)
      const blocked = new Set();
      g.players.forEach((p) => { if (!p.alive) return; p.body.forEach((c, k) => { if (!(p === me && k === p.body.length - 1)) blocked.add(key(c.x, c.y)); }); });
      const head = me.body[0];
      const order = [me.dir].concat(Object.keys(DIRS).filter((d) => d !== me.dir && d !== OPP[me.dir]));   // tout droit d'abord
      const safe = order.filter((d) => { const x = head.x + DIRS[d][0], y = head.y + DIRS[d][1]; return inside(x, y) && !blocked.has(key(x, y)); });
      if (!safe.length) return [];                                            // plus aucune issue : rien à faire
      const oh = other && other.alive ? other.body[0] : null;
      const risky = (d) => { if (!cfg.headOn || !oh) return false; const x = head.x + DIRS[d][0], y = head.y + DIRS[d][1]; return Math.abs(oh.x - x) + Math.abs(oh.y - y) === 1; };
      // Difficile : anticipe l'adversaire (les cases où sa tête peut aller comptent comme occupées pour mesurer la place)
      const roomBlocked = cfg.headOn && oh ? new Set(blocked) : blocked;
      if (roomBlocked !== blocked) Object.values(DIRS).forEach((v) => { const x = oh.x + v[0], y = oh.y + v[1]; if (inside(x, y)) roomBlocked.add(key(x, y)); });

      // 1. pomme visée : on la garde tant qu'elle existe (évite d'osciller entre deux pommes)
      if (!target || !g.food.some((f) => f.x === target.x && f.y === target.y)) target = pickFood(g, head, oh, cfg, rand, blocked);
      // 2. chemin le plus court vers elle
      let choice = null;
      if (target) {
        const dist = bfs(blocked, target.x, target.y);                       // distance de chaque case jusqu'à la pomme
        const ranked = safe.filter((d) => dist.has(key(head.x + DIRS[d][0], head.y + DIRS[d][1])))
          .sort((a, b) => dist.get(key(head.x + DIRS[a][0], head.y + DIRS[a][1])) - dist.get(key(head.x + DIRS[b][0], head.y + DIRS[b][1])));
        for (const d of ranked) {
          if (risky(d)) continue;
          if (cfg.flood && room(roomBlocked, head.x + DIRS[d][0], head.y + DIRS[d][1], me.body.length * cfg.flood + 2) < me.body.length * cfg.flood + 2) continue;   // piège
          choice = d; break;
        }
        if (!choice && !cfg.flood && ranked.length) choice = ranked[0];      // Facile : ne voit pas les pièges
      }
      // 3. secours : pas de chemin sûr vers la pomme -> la case qui laisse le plus de place (on survit en attendant)
      if (!choice) {
        let best = -1;
        for (const d of safe) { const r = room(roomBlocked, head.x + DIRS[d][0], head.y + DIRS[d][1], 400) - (risky(d) ? 50 : 0); if (r > best) { best = r; choice = d; } }
        target = null;
      }
      // 4. défauts « humains » du niveau : réflexe en retard (continue tout droit un tour si c'est sans danger)
      if (choice !== me.dir && safe.includes(me.dir) && rand() < cfg.lazy) choice = me.dir;
      // inattention très rare : se lance tout droit sans regarder
      if (rand() < cfg.blunder) choice = me.dir;
      return choice && choice !== me.dir ? [{ t: "dir", d: choice }] : [];
    },
  };
}
// Pomme visée : la plus proche (ou, en Facile, parfois une autre) ; en Difficile, celle où l'on arrive avant l'adversaire.
function pickFood(g, head, oh, cfg, rand, blocked) {
  if (!g.food.length) return null;
  const fromHead = bfs(blocked, head.x, head.y, true);
  const d = (f) => (fromHead.has(key(f.x, f.y)) ? fromHead.get(key(f.x, f.y)) : 999);
  let list = g.food.slice().sort((a, b) => d(a) - d(b));
  if (cfg.race && oh) {
    const mine = list.filter((f) => d(f) < Math.abs(oh.x - f.x) + Math.abs(oh.y - f.y));
    if (mine.length) list = mine;
  }
  const pick = rand() < cfg.nearest ? list[0] : list[Math.floor(rand() * list.length)];
  return { x: pick.x, y: pick.y };
}
// Parcours en largeur depuis (x, y) : distance de chaque case libre. startFree : la case de départ est occupée (tête).
function bfs(blocked, x, y, startFree) {
  const dist = new Map([[key(x, y), 0]]), todo = [[x, y]];
  if (!startFree && blocked.has(key(x, y))) return new Map();
  for (let h = 0; h < todo.length; h++) {
    const [cx, cy] = todo[h], dc = dist.get(key(cx, cy));
    for (const v of Object.values(DIRS)) {
      const nx = cx + v[0], ny = cy + v[1], k = key(nx, ny);
      if (!inside(nx, ny) || blocked.has(k) || dist.has(k)) continue;
      dist.set(k, dc + 1); todo.push([nx, ny]);
    }
  }
  return dist;
}
// Place libre accessible depuis une case (limitée à cap pour rester rapide).
function room(blocked, x, y, cap) {
  const seen = new Set([key(x, y)]), todo = [[x, y]];
  while (todo.length && seen.size < cap) {
    const [cx, cy] = todo.pop();
    for (const v of Object.values(DIRS)) {
      const nx = cx + v[0], ny = cy + v[1], k = key(nx, ny);
      if (!inside(nx, ny) || blocked.has(k) || seen.has(k)) continue;
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

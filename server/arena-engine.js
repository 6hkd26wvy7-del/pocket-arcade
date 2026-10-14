// Moteur de Snake Arena (2 joueurs). Aucune dépendance : tourne sur le serveur (Cloudflare) et dans les tests.
// Le serveur est le seul à décider de ce qui se passe : les téléphones envoient seulement une direction.

export const COLS = 24;
export const ROWS = 24;
export const TICK_MS = 140;
export const MAX_TICKS = Math.round(120000 / TICK_MS); // une partie dure 2 minutes au maximum
export const FOOD_COUNT = 3;

const DIRS = { U: { x: 0, y: -1 }, D: { x: 0, y: 1 }, L: { x: -1, y: 0 }, R: { x: 1, y: 0 } };

// Petit générateur aléatoire reproductible (même graine = même partie : utile pour les tests).
export function rng(seed) {
  let s = seed >>> 0 || 1;
  return function () {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function newGame(seed) {
  const rand = rng(seed);
  const g = {
    tick: 0,
    over: false,
    winner: null, // 0, 1, "draw" ou null
    reason: "",
    rand,
    food: [],
    players: [
      makeSnake(3, 12, "R"),
      makeSnake(COLS - 4, 12, "L"),
    ],
  };
  while (g.food.length < FOOD_COUNT) spawnFood(g);
  return g;
}

function makeSnake(x, y, dir) {
  const d = DIRS[dir];
  const body = [{ x, y }, { x: x - d.x, y: y - d.y }, { x: x - 2 * d.x, y: y - 2 * d.y }];
  return { body, dir, queue: [], alive: true, score: 0 };
}

function occupied(g, x, y) {
  for (const p of g.players) for (const c of p.body) if (c.x === x && c.y === y) return true;
  for (const f of g.food) if (f.x === x && f.y === y) return true;
  return false;
}

function spawnFood(g) {
  const free = [];
  for (let y = 0; y < ROWS; y++) for (let x = 0; x < COLS; x++) if (!occupied(g, x, y)) free.push({ x, y });
  if (!free.length) return;
  g.food.push(free[Math.floor(g.rand() * free.length)]);
}

// Un joueur demande à tourner. Les demi-tours sont ignorés, et on garde 2 ordres en attente au maximum.
export function setDirection(g, playerIndex, d) {
  const p = g.players[playerIndex];
  if (!p || !p.alive || g.over || !DIRS[d]) return false;
  const ref = p.queue.length ? p.queue[p.queue.length - 1] : p.dir;
  if (d === ref) return false;
  if (DIRS[d].x === -DIRS[ref].x && DIRS[d].y === -DIRS[ref].y) return false;
  if (p.queue.length >= 2) return false;
  p.queue.push(d);
  return true;
}

// Avance la partie d'un pas.
export function step(g) {
  if (g.over) return g;
  g.tick++;

  // 1. chacun prend sa nouvelle direction
  for (const p of g.players) {
    if (p.alive && p.queue.length) p.dir = p.queue.shift();
  }

  // 2. calcul des nouvelles têtes
  const heads = g.players.map((p) => {
    const d = DIRS[p.dir];
    return { x: p.body[0].x + d.x, y: p.body[0].y + d.y };
  });

  // 3. nourriture mangée ? (le serpent grandit : sa queue ne bouge pas ce tour-ci)
  const ate = g.players.map((p, i) => p.alive && g.food.some((f) => f.x === heads[i].x && f.y === heads[i].y));

  // 4. collisions, calculées avant tout déplacement pour être équitables
  const dead = [false, false];
  g.players.forEach((p, i) => {
    if (!p.alive) { dead[i] = true; return; }
    const h = heads[i];
    if (h.x < 0 || h.y < 0 || h.x >= COLS || h.y >= ROWS) { dead[i] = true; return; }
    g.players.forEach((q, j) => {
      if (!q.alive) return;
      // la queue libère sa case ce tour-ci, sauf si ce serpent vient de manger
      const tailFree = !ate[j];
      const limit = tailFree ? q.body.length - 1 : q.body.length;
      for (let k = 0; k < limit; k++) {
        if (q.body[k].x === h.x && q.body[k].y === h.y) dead[i] = true;
      }
    });
  });
  if (g.players[0].alive && g.players[1].alive && heads[0].x === heads[1].x && heads[0].y === heads[1].y) {
    dead[0] = true;
    dead[1] = true; // face à face : les deux perdent
  }

  // 5. déplacement des survivants
  g.players.forEach((p, i) => {
    if (!p.alive) return;
    if (dead[i]) { p.alive = false; return; }
    p.body.unshift(heads[i]);
    if (ate[i]) {
      p.score++;
      g.food = g.food.filter((f) => !(f.x === heads[i].x && f.y === heads[i].y));
    } else {
      p.body.pop();
    }
  });
  while (g.food.length < FOOD_COUNT) { const before = g.food.length; spawnFood(g); if (g.food.length === before) break; }

  // 6. fin de partie ?
  const alive = g.players.map((p) => p.alive);
  if (!alive[0] && !alive[1]) {
    g.over = true; g.winner = "draw"; g.reason = "double";
  } else if (!alive[0] || !alive[1]) {
    g.over = true; g.winner = alive[0] ? 0 : 1; g.reason = "crash";
  } else if (g.tick >= MAX_TICKS) {
    g.over = true; g.reason = "time";
    const a = g.players[0].score, b = g.players[1].score;
    g.winner = a === b ? "draw" : a > b ? 0 : 1;
  }
  return g;
}

// Ce que le serveur envoie aux téléphones.
export function snapshot(g) {
  return {
    t: "state",
    kind: "snake",
    tick: g.tick,
    over: g.over,
    winner: g.winner,
    reason: g.reason,
    food: g.food,
    players: g.players.map((p) => ({ body: p.body, alive: p.alive, score: p.score })),
  };
}

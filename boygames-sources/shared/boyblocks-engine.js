// BOYBLOCKS — moteur de jeu pur (aucune dépendance, aucune horloge, aucun hasard caché).
// Même code pour le téléphone (solo), le serveur de duels et la vérification des scores.
// Grille 8x8, 3 pièces proposées, placement libre, lignes/colonnes complètes effacées, combos.

export const SIZE = 8;

// Formes originales décrites en "dessin" : # = case pleine. Plusieurs colorId (1..7) pour les graphismes.
const SHAPES = [
  // [nom, poids de tirage, dessin]
  ["dot", 3, ["#"]],
  ["h2", 6, ["##"]], ["v2", 6, ["#", "#"]],
  ["h3", 7, ["###"]], ["v3", 7, ["#", "#", "#"]],
  ["h4", 4, ["####"]], ["v4", 4, ["#", "#", "#", "#"]],
  ["h5", 2, ["#####"]], ["v5", 2, ["#", "#", "#", "#", "#"]],
  ["sq2", 6, ["##", "##"]],
  ["sq3", 2, ["###", "###", "###"]],
  ["r23", 3, ["###", "###"]], ["r32", 3, ["##", "##", "##"]],
  ["c2a", 5, ["##", "# "]], ["c2b", 5, ["##", " #"]], ["c2c", 5, ["# ", "##"]], ["c2d", 5, [" #", "##"]],
  ["c3a", 3, ["###", "#  ", "#  "]], ["c3b", 3, ["###", "  #", "  #"]], ["c3c", 3, ["#  ", "#  ", "###"]], ["c3d", 3, ["  #", "  #", "###"]],
  ["t3a", 3, ["###", " # "]], ["t3b", 3, [" # ", "###"]], ["t3c", 3, ["# ", "##", "# "]], ["t3d", 3, [" #", "##", " #"]],
  ["z2a", 2, ["## ", " ##"]], ["z2b", 2, [" ##", "## "]], ["z2c", 2, [" #", "##", "# "]], ["z2d", 2, ["# ", "##", " #"]],
].map(function (s, i) {
  var cells = [];
  s[2].forEach(function (row, r) { for (var c = 0; c < row.length; c++) if (row[c] === "#") cells.push([r, c]); });
  var h = s[2].length, w = Math.max.apply(null, s[2].map(function (r) { return r.length; }));
  return { id: i, name: s[0], weight: s[1], cells: cells, h: h, w: w, n: cells.length };
});
export const PIECES = SHAPES;
const TOTAL_WEIGHT = SHAPES.reduce(function (a, s) { return a + s.weight; }, 0);

// ---- hasard reproductible (mulberry32) ----
export function rng(seed) {
  var a = seed >>> 0;
  return function () {
    a = (a + 0x6D2B79F5) >>> 0;
    var t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function mix(seed, index, salt) { // mélange de (graine, numéro de lot, essai) en une graine
  var h = (seed ^ Math.imul(index + 1, 0x9E3779B1) ^ Math.imul(salt + 1, 0x85EBCA6B)) >>> 0;
  h = Math.imul(h ^ (h >>> 16), 0x7FEB352D); h = Math.imul(h ^ (h >>> 15), 0x846CA68B);
  return (h ^ (h >>> 16)) >>> 0;
}
function drawPiece(r) {
  var x = r() * TOTAL_WEIGHT;
  for (var i = 0; i < SHAPES.length; i++) { x -= SHAPES[i].weight; if (x < 0) return i; }
  return SHAPES.length - 1;
}

export function emptyGrid() { return new Array(SIZE * SIZE).fill(0); }

export function fits(grid, shape, r, c) {
  for (var i = 0; i < shape.cells.length; i++) {
    var rr = r + shape.cells[i][0], cc = c + shape.cells[i][1];
    if (rr < 0 || cc < 0 || rr >= SIZE || cc >= SIZE || grid[rr * SIZE + cc]) return false;
  }
  return true;
}
export function canPlaceAnywhere(grid, shape) {
  for (var r = 0; r <= SIZE - shape.h; r++) for (var c = 0; c <= SIZE - shape.w; c++) if (fits(grid, shape, r, c)) return true;
  return false;
}

// Lot de 3 pièces n° `index`. Duel : identique pour les deux joueurs (ensureFit=false).
// Solo : on retente jusqu'à 12 fois pour qu'au moins une pièce rentre (probable, pas absolu ; reproductible donc vérifiable).
export function dealTriple(seed, index, grid, ensureFit) {
  var best = null;
  for (var salt = 0; salt < (ensureFit ? 12 : 1); salt++) {
    var r = rng(mix(seed, index, salt));
    var t = [drawPiece(r), drawPiece(r), drawPiece(r)];
    var colors = [1 + Math.floor(r() * 7), 1 + Math.floor(r() * 7), 1 + Math.floor(r() * 7)];
    var triple = t.map(function (p, i) { return { p: p, color: colors[i] }; });
    best = triple;
    if (!ensureFit || triple.some(function (x) { return canPlaceAnywhere(grid, SHAPES[x.p]); })) return triple;
  }
  return best;
}

export function newGame(seed, opts) {
  opts = opts || {};
  var g = {
    seed: seed >>> 0, ensureFit: opts.ensureFit !== false,
    grid: emptyGrid(), score: 0, streak: 0, best_streak: 0, lines: 0, moves: 0, index: 0, over: false,
    pieces: null, log: []
  };
  g.pieces = dealTriple(g.seed, 0, g.grid, g.ensureFit);
  checkOver(g);
  return g;
}

function checkOver(g) {
  g.over = !g.pieces.some(function (x) { return x && canPlaceAnywhere(g.grid, SHAPES[x.p]); });
}

// Points : 1 par case posée + lignes (10, 30, 60, 100…) x multiplicateur de combo (jusqu'à x4)
// + 300 si la grille est entièrement vidée.
export function lineBase(n) { return 10 * n * (n + 1) / 2; }
export function comboMult(streak) { return Math.min(4, 1 + 0.5 * (streak - 1)); }

export function place(g, slot, r, c) {
  if (g.over) return { ok: false, err: "over" };
  if (!Number.isInteger(slot) || slot < 0 || slot > 2 || !g.pieces[slot]) return { ok: false, err: "slot" };
  if (!Number.isInteger(r) || !Number.isInteger(c)) return { ok: false, err: "pos" };
  var piece = g.pieces[slot], shape = SHAPES[piece.p];
  if (!fits(g.grid, shape, r, c)) return { ok: false, err: "fit" };

  shape.cells.forEach(function (x) { g.grid[(r + x[0]) * SIZE + (c + x[1])] = piece.color; });
  var gain = shape.n;
  var rows = [], cols = [];
  for (var i = 0; i < SIZE; i++) {
    var fr = true, fc = true;
    for (var j = 0; j < SIZE; j++) { if (!g.grid[i * SIZE + j]) fr = false; if (!g.grid[j * SIZE + i]) fc = false; }
    if (fr) rows.push(i);
    if (fc) cols.push(i);
  }
  var n = rows.length + cols.length, cleared = [];
  if (n > 0) {
    rows.forEach(function (i) { for (var j = 0; j < SIZE; j++) cleared.push(i * SIZE + j); });
    cols.forEach(function (j) { for (var i2 = 0; i2 < SIZE; i2++) cleared.push(i2 * SIZE + j); });
    cleared.forEach(function (k) { g.grid[k] = 0; });
    g.streak++;
    if (g.streak > g.best_streak) g.best_streak = g.streak;
    gain += Math.round(lineBase(n) * comboMult(g.streak));
    g.lines += n;
  } else {
    g.streak = 0;
  }
  var allClear = n > 0 && g.grid.every(function (v) { return !v; });
  if (allClear) gain += 300;
  g.score += gain;
  g.moves++;
  g.log.push([slot, r, c]);
  g.pieces[slot] = null;
  var dealt = false;
  if (g.pieces.every(function (x) { return !x; })) {
    g.index++;
    g.pieces = dealTriple(g.seed, g.index, g.grid, g.ensureFit);
    dealt = true;
  }
  checkOver(g);
  return { ok: true, gain: gain, rows: rows, cols: cols, lines: n, cleared: cleared, streak: g.streak, allClear: allClear, dealt: dealt, over: g.over };
}

// Rejoue une partie complète (vérification des scores côté serveur).
export function replay(seed, moves, opts) {
  var g = newGame(seed, opts);
  for (var i = 0; i < moves.length; i++) {
    var m = moves[i];
    var res = place(g, m[0], m[1], m[2]);
    if (!res.ok) return { ok: false, at: i, err: res.err, game: g };
  }
  return { ok: true, game: g };
}

// Plafond théorique par coup (borne anti-triche simple quand on ne rejoue pas la partie).
export const MAX_GAIN_PER_MOVE = 25 + Math.round(lineBase(8 + 8) * 4) + 300;

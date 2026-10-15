// BOYBLOCKS — moteur de jeu pur (aucune dépendance, aucune horloge, aucun hasard caché).
// Même code pour le téléphone (solo), le serveur de duels et la vérification des scores.
// Grille 8x8, 3 pièces proposées, placement libre, lignes/colonnes complètes effacées, combos.

export const SIZE = 8;              // grille classique ; la grille d'essai 9x9 est choisie par newGame(seed, { size: 9 })
export const SIZES = [8, 9];
function sizeOf(grid) { return grid.length === 81 ? 9 : 8; }

// Formes originales décrites en "dessin" : # = case pleine. Plusieurs colorId (1..7) pour les graphismes.
// Fréquences propres à la grille 9x9 (81 cases) : plus de grandes pièces pour garder le défi. Absent = même poids qu'en 8x8.
const WEIGHT9 = {};
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
  var rowN = [], colN = [];   // nombre de cases de la pièce sur chacune de ses lignes / colonnes
  for (var k = 0; k < h; k++) rowN.push(0);
  for (var k2 = 0; k2 < w; k2++) colN.push(0);
  cells.forEach(function (x) { rowN[x[0]]++; colN[x[1]]++; });
  return { id: i, name: s[0], weight: s[1], weight9: WEIGHT9[s[0]] !== undefined ? WEIGHT9[s[0]] : s[1], cells: cells, h: h, w: w, n: cells.length, rowN: rowN, colN: colN };
});
export const PIECES = SHAPES;
const TOTAL_WEIGHT = SHAPES.reduce(function (a, s) { return a + s.weight; }, 0);
const TOTAL_WEIGHT9 = SHAPES.reduce(function (a, s) { return a + s.weight9; }, 0);

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
function drawPiece(r, size) {
  var nine = size === 9, x = r() * (nine ? TOTAL_WEIGHT9 : TOTAL_WEIGHT);
  for (var i = 0; i < SHAPES.length; i++) { x -= nine ? SHAPES[i].weight9 : SHAPES[i].weight; if (x < 0) return i; }
  return SHAPES.length - 1;
}

export function emptyGrid(size) { size = size === 9 ? 9 : SIZE; return new Array(size * size).fill(0); }

export function fits(grid, shape, r, c) {
  var n = sizeOf(grid);
  for (var i = 0; i < shape.cells.length; i++) {
    var rr = r + shape.cells[i][0], cc = c + shape.cells[i][1];
    if (rr < 0 || cc < 0 || rr >= n || cc >= n || grid[rr * n + cc]) return false;
  }
  return true;
}
export function canPlaceAnywhere(grid, shape) {
  var n = sizeOf(grid);
  for (var r = 0; r <= n - shape.h; r++) for (var c = 0; c <= n - shape.w; c++) if (fits(grid, shape, r, c)) return true;
  return false;
}

// Tirage d'un lot « au hasard » (règles 1) : 3 pièces et 3 couleurs à partir de (graine, numéro de lot, essai).
function rawTriple(seed, index, salt, size) {
  var r = rng(mix(seed, index, salt));
  var t = [drawPiece(r, size), drawPiece(r, size), drawPiece(r, size)];
  var colors = [1 + Math.floor(r() * 7), 1 + Math.floor(r() * 7), 1 + Math.floor(r() * 7)];
  return t.map(function (p, i) { return { p: p, color: colors[i] }; });
}

// Règles 1 (et duels) : au hasard ; en solo on retente jusqu'à 12 fois pour qu'au moins une pièce rentre.
function dealRandom(seed, index, grid, ensureFit) {
  var best = null;
  for (var salt = 0; salt < (ensureFit ? 12 : 1); salt++) {
    var triple = rawTriple(seed, index, salt, sizeOf(grid));
    best = triple;
    if (!ensureFit || triple.some(function (x) { return canPlaceAnywhere(grid, SHAPES[x.p]); })) return triple;
  }
  return best;
}

// Règles 2 (solo) : tirage « stratégique », façon mode classique de Block Blast.
// On compare 4 lots candidats et on note chacun d'après la grille : pièces posables, lignes qu'elles peuvent
// compléter, possibilité d'enchaîner plusieurs lignes (combo). 70 % du temps on garde le lot le plus
// intéressant, 30 % du temps on garde le tirage au hasard : le jeu n'est jamais garanti gagnable.
// Calculs uniquement sur des entiers : la base de données refait exactement le même choix (bb_deal2).
export const STRATEGY = { candidates: 4, percent: 70, choiceSalt: 97 };
function emptiesOf(grid) {
  var n = sizeOf(grid), re = [], ce = [];
  for (var i = 0; i < n; i++) { re.push(0); ce.push(0); }
  for (var r = 0; r < n; r++) for (var c = 0; c < n; c++) if (!grid[r * n + c]) { re[r]++; ce[c]++; }
  return { re: re, ce: ce };
}
// [nombre de positions possibles, meilleur nombre de lignes/colonnes complétées en un coup]
export function pieceOutlook(grid, em, shape) {
  var fitsN = 0, best = 0, n = sizeOf(grid);
  for (var r = 0; r <= n - shape.h; r++) for (var c = 0; c <= n - shape.w; c++) {
    if (!fits(grid, shape, r, c)) continue;
    fitsN++;
    var lines = 0;
    for (var dr = 0; dr < shape.h; dr++) if (em.re[r + dr] === shape.rowN[dr]) lines++;
    for (var dc = 0; dc < shape.w; dc++) if (em.ce[c + dc] === shape.colN[dc]) lines++;
    if (lines > best) best = lines;
  }
  return [fitsN, best];
}
export function tripleQuality(grid, triple) {
  var em = emptiesOf(grid), q = 0, clearing = 0;
  triple.forEach(function (x) {
    var o = pieceOutlook(grid, em, SHAPES[x.p]);
    q += o[0] === 0 ? -30 : 10 + Math.min(o[0], 3);
    q += 12 * o[1];
    if (o[1] > 0) clearing++;
  });
  if (clearing >= 2) q += 8;
  return q;
}
function dealStrategic(seed, index, grid) {
  var pick = Math.floor(rng(mix(seed, index, STRATEGY.choiceSalt))() * 100);
  if (pick >= STRATEGY.percent) return dealRandom(seed, index, grid, true);
  var best = null, bestQ = 0;
  for (var salt = 0; salt < STRATEGY.candidates; salt++) {
    var t = rawTriple(seed, index, salt, sizeOf(grid)), q = tripleQuality(grid, t);
    if (best === null || q > bestQ) { best = t; bestQ = q; }
  }
  return best;
}

// Lot de 3 pièces n° `index`. Duel : identique pour les deux joueurs (ensureFit=false, toujours au hasard).
export function dealTriple(seed, index, grid, ensureFit, rules) {
  if (ensureFit && rules === 2) return dealStrategic(seed, index, grid);
  return dealRandom(seed, index, grid, ensureFit);
}

export function newGame(seed, opts) {
  opts = opts || {};
  var g = {
    seed: seed >>> 0, ensureFit: opts.ensureFit !== false, rules: opts.rules === 2 ? 2 : 1, size: opts.size === 9 ? 9 : 8,
    grid: emptyGrid(opts.size), score: 0, streak: 0, best_streak: 0, lines: 0, moves: 0, index: 0, over: false,
    pieces: null, log: []
  };
  g.pieces = dealTriple(g.seed, 0, g.grid, g.ensureFit, g.rules);
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

  var N = g.size || SIZE;
  shape.cells.forEach(function (x) { g.grid[(r + x[0]) * N + (c + x[1])] = piece.color; });
  var gain = shape.n;
  var rows = [], cols = [];
  for (var i = 0; i < N; i++) {
    var fr = true, fc = true;
    for (var j = 0; j < N; j++) { if (!g.grid[i * N + j]) fr = false; if (!g.grid[j * N + i]) fc = false; }
    if (fr) rows.push(i);
    if (fc) cols.push(i);
  }
  var n = rows.length + cols.length, cleared = [];
  if (n > 0) {
    rows.forEach(function (i) { for (var j = 0; j < N; j++) cleared.push(i * N + j); });
    cols.forEach(function (j) { for (var i2 = 0; i2 < N; i2++) cleared.push(i2 * N + j); });
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
    g.pieces = dealTriple(g.seed, g.index, g.grid, g.ensureFit, g.rules);
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

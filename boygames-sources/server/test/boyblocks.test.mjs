import assert from "node:assert/strict";
import * as BB from "../boyblocks-engine.js";

let n = 0; const t = (name, fn) => { fn(); n++; console.log("ok -", name); };
const shape = (name) => BB.PIECES.find((p) => p.name === name);
// Grille presque pleine : 16 cases vides isolées (2 par ligne et par colonne), donc aucune ligne complète, aucune place pour 2 cases.
function isoGrid() { const g = new Array(64).fill(1); for (let r = 0; r < 8; r++) { g[r * 8 + r] = 0; g[r * 8 + ((r + 4) % 8)] = 0; } return g; }
function setPieces(g, names) { g.pieces = names.map((nm, i) => (nm ? { p: shape(nm).id, color: 1 + i } : null)); }

t("formes : toutes valides, tiennent dans la grille, cases uniques", () => {
  assert.ok(BB.PIECES.length >= 25);
  for (const p of BB.PIECES) {
    assert.ok(p.n >= 1 && p.h <= 8 && p.w <= 8);
    assert.equal(new Set(p.cells.map((c) => c.join())).size, p.n);
  }
});

t("graine identique = mêmes lots (pour les deux joueurs d'un duel), graines différentes = lots différents", () => {
  const a = BB.newGame(12345, { ensureFit: false }), b = BB.newGame(12345, { ensureFit: false });
  assert.deepEqual(a.pieces, b.pieces);
  for (let i = 0; i < 50; i++) assert.deepEqual(BB.dealTriple(777, i, BB.emptyGrid(), false), BB.dealTriple(777, i, BB.emptyGrid(), false));
  let diff = 0; for (let i = 0; i < 50; i++) if (JSON.stringify(BB.dealTriple(1, i, BB.emptyGrid(), false)) !== JSON.stringify(BB.dealTriple(2, i, BB.emptyGrid(), false))) diff++;
  assert.ok(diff > 40);
});

t("placement : refuse hors grille, case occupée, mauvais emplacement, mauvaise pièce", () => {
  const g = BB.newGame(1); setPieces(g, ["h3", "dot", "v2"]);
  assert.equal(BB.place(g, 0, 0, 6).err, "fit");
  assert.equal(BB.place(g, 0, -1, 0).err, "fit");
  assert.equal(BB.place(g, 5, 0, 0).err, "slot");
  assert.equal(BB.place(g, 0, 1.5, 0).err, "pos");
  assert.ok(BB.place(g, 0, 0, 0).ok);
  assert.equal(BB.place(g, 0, 3, 3).err, "slot");     // déjà posée
  assert.equal(BB.place(g, 1, 0, 1).err, "fit");      // case occupée
});

t("une ligne complète disparaît et rapporte des points avec combo", () => {
  const g = BB.newGame(1); g.grid.fill(0); for (let c = 0; c < 6; c++) g.grid[3 * 8 + c] = 2;
  setPieces(g, ["h2", "dot", "dot"]);
  const r = BB.place(g, 0, 3, 6);
  assert.equal(r.lines, 1); assert.deepEqual(r.rows, [3]);
  assert.equal(r.gain, 2 + BB.lineBase(1) * 1 + 300);   // 2 cases + 10 + grille vide (+300)
  assert.ok(r.allClear);
  assert.equal(g.grid.every((v) => v === 0), true);
});

t("ligne + colonne en même temps : 2 lignes comptées, case commune effacée une fois", () => {
  const g = BB.newGame(1); g.grid.fill(0);
  for (let c = 0; c < 8; c++) if (c !== 4) g.grid[2 * 8 + c] = 1;
  for (let r = 0; r < 8; r++) if (r !== 2) g.grid[r * 8 + 4] = 1;
  g.grid[0] = 5; // pour ne pas vider la grille
  setPieces(g, ["dot", "dot", "dot"]);
  const r = BB.place(g, 0, 2, 4);
  assert.equal(r.lines, 2); assert.equal(new Set(r.cleared).size, 15);
  assert.equal(r.gain, 1 + BB.lineBase(2));
  assert.equal(g.grid[0], 5);
});

t("combo : les placements qui effacent s'enchaînent (x1, x1.5, x2…), une pose sans ligne remet à zéro", () => {
  assert.equal(BB.comboMult(1), 1); assert.equal(BB.comboMult(2), 1.5); assert.equal(BB.comboMult(3), 2); assert.equal(BB.comboMult(9), 4);
  const g = BB.newGame(1); g.grid.fill(0);
  for (let c = 0; c < 7; c++) { g.grid[0 * 8 + c] = 1; g.grid[1 * 8 + c] = 1; g.grid[7 * 8 + 7 - c - 0 * 0] = 0; }
  g.grid[5 * 8 + 5] = 3; // garde la grille non vide
  setPieces(g, ["dot", "dot", "dot"]);
  const a = BB.place(g, 0, 0, 7); assert.equal(g.streak, 1);
  const b = BB.place(g, 1, 1, 7); assert.equal(g.streak, 2); assert.equal(b.gain, 1 + Math.round(BB.lineBase(1) * 1.5));
  const c = BB.place(g, 2, 4, 4); assert.equal(c.lines, 0); assert.equal(g.streak, 0);
});

t("nouveau lot de 3 pièces quand les trois sont posées", () => {
  const g = BB.newGame(9); g.grid.fill(0); setPieces(g, ["dot", "dot", "dot"]);
  BB.place(g, 0, 0, 0); BB.place(g, 1, 0, 2); const r = BB.place(g, 2, 0, 4);
  assert.ok(r.dealt); assert.equal(g.index, 1); assert.ok(g.pieces.every(Boolean));
});

t("fin de partie : plus aucune pièce ne peut être posée => over", () => {
  const g = BB.newGame(1); g.grid = isoGrid();
  setPieces(g, ["dot", "h2", "v2"]); g.over = false;
  assert.equal(g.pieces.some((x) => x && BB.canPlaceAnywhere(g.grid, BB.PIECES[x.p])), true);
  const r = BB.place(g, 0, 0, 0);
  assert.ok(r.ok); assert.equal(r.lines, 0);
  assert.equal(r.over, true); assert.equal(g.over, true);
  assert.equal(BB.place(g, 1, 0, 2).err, "over");        // plus aucun coup accepté
});

t("solo : les nouvelles tentatives rendent un lot jouable bien plus probable", () => {
  const grid = isoGrid();                                         // seulement des places d'une case
  let withFit = 0, without = 0;
  for (let s = 0; s < 400; s++) {
    if (BB.dealTriple(s, 3, grid, true).some((x) => BB.canPlaceAnywhere(grid, BB.PIECES[x.p]))) withFit++;
    if (BB.dealTriple(s, 3, grid, false).some((x) => BB.canPlaceAnywhere(grid, BB.PIECES[x.p]))) without++;
  }
  assert.ok(withFit > without * 3, withFit + " vs " + without);
  const open = BB.emptyGrid();
  for (let s = 0; s < 100; s++) assert.ok(BB.dealTriple(s, 5, open, true).some((x) => BB.canPlaceAnywhere(open, BB.PIECES[x.p])));
});

function bot(seed, ensureFit, r) {
  const g = BB.newGame(seed, { ensureFit });
  let guard = 0;
  while (!g.over && guard++ < 5000) {
    const opts = [];
    for (let s = 0; s < 3; s++) if (g.pieces[s]) { const sh = BB.PIECES[g.pieces[s].p]; for (let a = 0; a <= 8 - sh.h; a++) for (let b = 0; b <= 8 - sh.w; b++) if (BB.fits(g.grid, sh, a, b)) opts.push([s, a, b]); }
    if (!opts.length) break;
    const m = opts[Math.floor(r() * opts.length)];
    assert.ok(BB.place(g, m[0], m[1], m[2]).ok);
  }
  return g;
}

t("500 parties au hasard : finissent toujours, score cohérent, la rediffusion donne le même résultat", () => {
  const r = BB.rng(2024); let maxMoves = 0;
  for (let i = 0; i < 500; i++) {
    const g = bot(i + 1, i % 2 === 0, r);
    assert.ok(g.over, "partie " + i + " sans fin");
    assert.ok(g.score >= g.moves);
    const rp = BB.replay(g.seed, g.log, { ensureFit: g.ensureFit });
    assert.ok(rp.ok); assert.equal(rp.game.score, g.score); assert.deepEqual(rp.game.grid, g.grid);
    maxMoves = Math.max(maxMoves, g.moves);
  }
  assert.ok(maxMoves > 5);
});

t("anti-triche : coup après la fin, coup rejoué ou emplacement impossible => rejetés par la rediffusion", () => {
  const g = bot(5, true, BB.rng(1));
  assert.ok(g.over && g.log.length > 3);
  const after = BB.replay(g.seed, [...g.log, [0, 0, 0]], { ensureFit: true });
  assert.equal(after.ok, false); assert.equal(after.err, "over"); assert.equal(after.at, g.log.length);
  const twice = BB.replay(g.seed, [g.log[0], g.log[0]], { ensureFit: true });
  assert.equal(twice.ok, false);
  const off = BB.replay(g.seed, [[0, 8, 8]], { ensureFit: true });
  assert.equal(off.ok, false); assert.equal(off.err, "fit");
  const same = BB.replay(g.seed, g.log, { ensureFit: true });
  assert.equal(same.ok, true); assert.equal(same.game.score, g.score);
  assert.notEqual(same.game.score, g.score + 1);          // un score annoncé plus haut ne correspondrait pas
});

t("score maximal par coup : jamais dépassé en jeu aléatoire", () => {
  const r = BB.rng(7);
  for (let i = 0; i < 100; i++) { const g = BB.newGame(i, { ensureFit: true }); let last = 0; let guard = 0;
    while (!g.over && guard++ < 2000) { const s = g.pieces.findIndex(Boolean); const sh = BB.PIECES[g.pieces[s].p]; let done = false;
      for (let a = 0; a <= 8 - sh.h && !done; a++) for (let b = 0; b <= 8 - sh.w && !done; b++) if (BB.fits(g.grid, sh, a, b)) { const res = BB.place(g, s, a, b); assert.ok(res.gain <= BB.MAX_GAIN_PER_MOVE); done = true; }
      if (!done) break; } }
});
console.log(n + " tests OK");

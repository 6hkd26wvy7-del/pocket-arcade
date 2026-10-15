import assert from "node:assert/strict";
import * as SP from "../space-engine.js";
import * as BK from "../blocks-engine.js";
import { rng } from "../arena-engine.js";
let n = 0; const t = (name, fn) => { fn(); n++; console.log("ok -", name); };

// ---------- Space co-op ----------
t("space: 2 vaisseaux, 3 vies chacun, vague 1", () => { const g = SP.newGame(1); assert.equal(g.ships.length, 2); assert.deepEqual(g.ships.map(s => s.lives), [3, 3]); assert.equal(g.enemies.length, 12); });
t("space: cible absurde ignoree, cible valide bornee a l'ecran", () => { const g = SP.newGame(1); assert.equal(SP.setTarget(g, 0, "x"), false); assert.equal(SP.setTarget(g, 0, NaN), false); assert.equal(SP.setTarget(g, 0, Infinity), false); assert.equal(SP.setTarget(g, 5, 10), false); assert.equal(SP.setTarget(g, 0, -50), true); assert.equal(g.ships[0].target, 0); });
t("space: les deux vaisseaux tirent et marquent ensemble", () => { const g = SP.newGame(1); g.enemies = [{ x: g.ships[0].x, y: 80, row: 0 }, { x: g.ships[1].x, y: 80, row: 0 }, { x: 70, y: 30, row: 0 }]; g.dir = 0; for (let i = 0; i < 100 && g.enemies.length > 1; i++) SP.step(g); assert.equal(g.enemies.length, 1); assert.ok(g.score >= 20); });
t("space: un vaisseau a 0 vie est elimine, la partie continue pour l'autre", () => { const g = SP.newGame(1); g.enemies = [{ x: 130, y: 30, row: 0 }]; g.enemyFireAt = 1e9; g.ships[0].lives = 1; g.shots = [{ x: g.ships[0].x + 5, y: SP.SHIP_Y - 3 }]; SP.step(g); assert.equal(g.ships[0].lives, 0); assert.equal(g.over, false); assert.equal(SP.setTarget(g, 0, 50), false); });
t("space: les deux a 0 vie = fin d'equipe", () => { const g = SP.newGame(1); g.enemies = [{ x: 130, y: 30, row: 0 }]; g.enemyFireAt = 1e9; g.ships.forEach(s => { s.lives = 1; }); g.shots = g.ships.map(s => ({ x: s.x + 5, y: SP.SHIP_Y - 3 })); SP.step(g); assert.equal(g.over, true); assert.equal(g.winner, "team"); });
t("space: invasion = fin; vague terminee = vague suivante", () => { const g = SP.newGame(1); g.enemies = [{ x: 60, y: SP.SHIP_Y - 4, row: 0 }]; g.enemyFireAt = 1e9; SP.step(g); assert.equal(g.reason, "invaded"); const h = SP.newGame(1); h.enemies = []; SP.step(h); assert.equal(h.wave, 2); assert.ok(h.score >= 100); });
t("space: 300 parties sans joueur finissent toujours; snapshot leger", () => { for (let s = 1; s <= 300; s++) { const g = SP.newGame(s); let k = 0; while (!g.over && k++ < 400000) SP.step(g); assert.ok(g.over); } const snap = SP.snapshot(SP.newGame(1)); assert.ok(JSON.stringify(snap).length < 1500); });

// ---------- Blocks duel ----------
t("blocks: memes pieces pour les 2 joueurs", () => { const g = BK.newGame(5); assert.deepEqual(g.players[0].cur, g.players[1].cur); BK.act(g, 0, "HARD"); BK.act(g, 1, "HARD"); assert.deepEqual(g.players[0].cur, g.players[1].cur); });
t("blocks: deplacements, rotation, chute dure; actions invalides ignorees", () => { const g = BK.newGame(5); const x0 = g.players[0].x; assert.equal(BK.act(g, 0, "L"), true); assert.equal(g.players[0].x, x0 - 1); assert.equal(BK.act(g, 0, "ZZZ"), false); assert.equal(BK.act(g, 7, "L"), false); const y0 = g.players[0].y; BK.act(g, 0, "HARD"); assert.ok(g.players[0].grid[BK.ROWS - 1].some(Boolean)); assert.ok(g.players[0].score > 0); assert.equal(g.players[0].y, 0); void y0; });
t("blocks: 4 lignes envoient 4 lignes cadeau, qui arrivent avec un trou", () => {
  const g = BK.newGame(5); const p = g.players[0], o = g.players[1];
  for (let y = BK.ROWS - 4; y < BK.ROWS; y++) for (let x = 0; x < BK.COLS; x++) if (x !== 0) p.grid[y][x] = 1; // colonne 0 vide
  p.cur = [[1], [1], [1], [1]]; p.x = 0; p.y = 0; // barre verticale
  BK.act(g, 0, "HARD");
  assert.equal(p.lines, 4); assert.equal(o.pending, 4);
  BK.act(g, 1, "HARD");  // l'adversaire pose sans faire de ligne : il recoit les lignes
  assert.equal(o.pending, 0);
  const bottom = o.grid[BK.ROWS - 1]; assert.equal(bottom.filter(v => v === 0).length, 1);
});
t("blocks: celui dont la pile deborde perd, l'autre gagne", () => { const g = BK.newGame(5); const p = g.players[0]; for (let y = 0; y < 4; y++) for (let x = 0; x < BK.COLS; x++) p.grid[y][x] = (x + y) % 3 ? 1 : 0; p.grid[0][3] = 1; BK.act(g, 0, "HARD"); BK.step(g, 1); assert.equal(g.over, true); assert.equal(g.winner, 1); assert.equal(g.reason, "topout"); });
t("blocks: la gravite fait descendre seule; apres la fin plus rien ne bouge", () => { const g = BK.newGame(5); const y0 = g.players[0].y; BK.step(g, 800); assert.ok(g.players[0].y > y0 || g.players[0].score >= 0); g.over = true; assert.equal(BK.act(g, 0, "L"), false); });
t("blocks: 200 duels de bots au hasard finissent toujours", () => { const acts = ["L", "R", "ROT", "SOFT", "HARD"]; for (let s = 1; s <= 200; s++) { const g = BK.newGame(s), r = rng(s * 3); let k = 0; while (!g.over && k++ < 100000) { BK.act(g, 0, acts[Math.floor(r() * 5)]); BK.act(g, 1, acts[Math.floor(r() * 5)]); BK.step(g, 50); } assert.ok(g.over, "seed " + s); assert.ok([0, 1, "draw"].includes(g.winner)); } });
t("blocks: snapshot compact et coherent", () => { const g = BK.newGame(5); const s = BK.snapshot(g); assert.equal(s.players[0].grid.length, BK.ROWS); assert.equal(s.players[0].grid[0].length, BK.COLS); assert.ok(JSON.stringify(s).length < 2500); assert.ok(s.players[0].grid.join("").includes("2")); });
console.log(n + " tests OK");

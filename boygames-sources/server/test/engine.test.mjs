import assert from "node:assert/strict";
import { newGame, step, setDirection, snapshot, COLS, ROWS, MAX_TICKS, rng } from "../arena-engine.js";
let n = 0; const t = (name, fn) => { fn(); n++; console.log("ok -", name); };

t("depart: 2 serpents de 3 cases, 3 fruits, aucun chevauchement", () => {
  const g = newGame(1);
  assert.equal(g.players[0].body.length, 3); assert.equal(g.players[1].body.length, 3);
  assert.equal(g.food.length, 3);
  const cells = new Set(); [...g.players[0].body, ...g.players[1].body, ...g.food].forEach(c => { const k = c.x+","+c.y; assert.ok(!cells.has(k)); cells.add(k); });
});
t("meme graine = meme partie", () => {
  const a = newGame(42), b = newGame(42); assert.deepEqual(a.food, b.food);
  const r1 = rng(7), r2 = rng(7); assert.equal(r1(), r2());
});
t("demi-tour interdit, direction invalide ignoree, file limitee a 2", () => {
  const g = newGame(1);
  assert.equal(setDirection(g, 0, "L"), false);       // joueur 0 va vers R
  assert.equal(setDirection(g, 0, "X"), false);
  assert.equal(setDirection(g, 0, "R"), false);       // meme direction
  assert.equal(setDirection(g, 0, "U"), true);
  assert.equal(setDirection(g, 0, "L"), true);        // U puis L possible (pas un demi-tour de U)
  assert.equal(setDirection(g, 0, "D"), false);       // file pleine
  assert.equal(setDirection(g, 5, "U"), false);       // joueur inexistant
});
t("avance d'une case par pas, sans grandir", () => {
  const g = newGame(1); const h = g.players[0].body[0]; g.food = [];
  step(g);
  assert.equal(g.players[0].body[0].x, h.x + 1); assert.equal(g.players[0].body.length, 3);
});
t("manger fait grandir et marque 1 point, un fruit reapparait", () => {
  const g = newGame(1); const h = g.players[0].body[0];
  g.food = [{ x: h.x + 1, y: h.y }, { x: 0, y: 0 }, { x: 1, y: 0 }];
  step(g);
  assert.equal(g.players[0].score, 1); assert.equal(g.players[0].body.length, 4); assert.equal(g.food.length, 3);
});
t("mur: celui qui sort perd, l'autre gagne", () => {
  const g = newGame(1); g.food = [];
  g.players[0].body = [{ x: COLS - 1, y: 5 }, { x: COLS - 2, y: 5 }, { x: COLS - 3, y: 5 }]; g.players[0].dir = "R";
  step(g);
  assert.equal(g.over, true); assert.equal(g.winner, 1); assert.equal(g.reason, "crash"); assert.equal(g.players[0].alive, false);
});
t("face a face sur la meme case: match nul", () => {
  const g = newGame(1); g.food = [];
  g.players[0].body = [{ x: 10, y: 5 }, { x: 9, y: 5 }, { x: 8, y: 5 }]; g.players[0].dir = "R";
  g.players[1].body = [{ x: 12, y: 5 }, { x: 13, y: 5 }, { x: 14, y: 5 }]; g.players[1].dir = "L";
  step(g);
  assert.equal(g.over, true); assert.equal(g.winner, "draw");
});
t("percuter le corps de l'autre: on perd", () => {
  const g = newGame(1); g.food = [];
  g.players[0].body = [{ x: 5, y: 5 }, { x: 4, y: 5 }, { x: 3, y: 5 }]; g.players[0].dir = "R";
  g.players[1].body = [{ x: 6, y: 4 }, { x: 6, y: 5 }, { x: 6, y: 6 }, { x: 6, y: 7 }]; g.players[1].dir = "U";
  step(g);
  assert.equal(g.players[0].alive, false); assert.equal(g.winner, 1);
});
t("se mordre la queue: on perd, mais suivre sa propre queue est permis", () => {
  const g = newGame(1); g.food = [];
  // carre de 4 cases: la tete va prendre la place de la queue qui part ce tour-ci => autorise
  g.players[0].body = [{ x: 5, y: 5 }, { x: 5, y: 6 }, { x: 6, y: 6 }, { x: 6, y: 5 }]; g.players[0].dir = "R";
  g.players[1].body = [{ x: 20, y: 20 }, { x: 21, y: 20 }, { x: 22, y: 20 }]; g.players[1].dir = "L";
  step(g);
  assert.equal(g.players[0].alive, true);
});
t("fin au temps: le meilleur score gagne", () => {
  const g = newGame(1); g.food = []; g.tick = MAX_TICKS - 1; g.players[0].score = 4; g.players[1].score = 2;
  g.players[0].body = [{ x: 5, y: 5 }, { x: 4, y: 5 }, { x: 3, y: 5 }]; g.players[0].dir = "R";
  g.players[1].body = [{ x: 20, y: 20 }, { x: 21, y: 20 }, { x: 22, y: 20 }]; g.players[1].dir = "L";
  step(g);
  assert.equal(g.over, true); assert.equal(g.reason, "time"); assert.equal(g.winner, 0);
});
t("apres la fin, plus rien ne bouge ni ne se commande", () => {
  const g = newGame(1); g.over = true; const before = JSON.stringify(snapshot(g));
  step(g); assert.equal(JSON.stringify(snapshot(g)), before); assert.equal(setDirection(g, 0, "U"), false);
});
t("1000 parties au hasard: toujours une fin valide, jamais de crash", () => {
  const dirs = ["U", "D", "L", "R"];
  for (let seed = 1; seed <= 1000; seed++) {
    const g = newGame(seed); const r = rng(seed * 7);
    let guard = 0;
    while (!g.over && guard++ < 2000) {
      setDirection(g, 0, dirs[Math.floor(r() * 4)]); setDirection(g, 1, dirs[Math.floor(r() * 4)]); step(g);
      for (const p of g.players) if (p.alive) for (const c of p.body) assert.ok(c.x >= 0 && c.y >= 0 && c.x < COLS && c.y < ROWS);
    }
    assert.ok(g.over, "partie infinie seed " + seed); assert.ok([0, 1, "draw"].includes(g.winner));
  }
});
console.log(n + " tests OK");

// Logique de Snake (grille pleine, presque pleine, génération de nourriture) : extraite de src/app-fragment.html entre les marqueurs SNAKE-LOGIC.
import assert from "node:assert/strict";
import fs from "node:fs";
const src = fs.readFileSync(new URL("../../src/app-fragment.html", import.meta.url), "utf8");
const code = src.slice(src.indexOf("/*SNAKE-LOGIC-START*/"), src.indexOf("/*SNAKE-LOGIC-END*/"));
const SNK = new Function(code + "\nreturn SNK;")();
const COLS = 18, ROWS = 24;      // = 144 / 8 et (208 - 16) / 8, comme dans le jeu
let n = 0; const t = (name, fn) => { fn(); n++; console.log("  ok", name); };
// parcours en serpentin qui couvre toute la grille (cycle : lignes en boustrophédon)
const path = []; for (let y = 0; y < ROWS; y++) for (let x = 0; x < COLS; x++) path.push({ x: y % 2 ? COLS - 1 - x : x, y });

t("score maximal = cases de la grille moins le serpent de départ (429), égal à la limite serveur de Snake", () => {
  assert.equal(SNK.maxScore(COLS, ROWS), 429);
  assert.match(fs.readFileSync(new URL("../../sql/schema_all.sql", import.meta.url), "utf8"), /when 'snake' then 429/);
});
t("grille pleine : aucune case libre, nourriture = null immédiatement (pas de boucle), victoire détectée", () => {
  const body = path.slice().reverse();
  const t0 = Date.now();
  assert.equal(SNK.freeCells(body, COLS, ROWS).length, 0);
  assert.equal(SNK.pickFood(body, COLS, ROWS, Math.random), null);
  assert.equal(SNK.isFull(body, COLS, ROWS), true);
  assert.ok(Date.now() - t0 < 100);
});
t("grille presque pleine : la seule case libre est toujours choisie, quel que soit le tirage (0, 0.5, 0.999999, 1)", () => {
  for (const r of [0, 0.5, 0.999999, 1]) {
    const body = path.slice(0, -1);            // une case libre : la dernière du parcours
    const f = SNK.pickFood(body, COLS, ROWS, () => r);
    assert.deepEqual(f, path[path.length - 1]); assert.equal(SNK.isFull(body, COLS, ROWS), false);
  }
});
t("deux cases libres : la nourriture est l'une des deux, jamais sur le serpent", () => {
  const body = path.slice(0, -2), free = new Set(path.slice(-2).map((c) => c.x + "," + c.y));
  for (const r of [0, 0.3, 0.7, 0.9999]) { const f = SNK.pickFood(body, COLS, ROWS, () => r); assert.ok(free.has(f.x + "," + f.y)); }
});
t("partie complète simulée : le serpent suit le parcours, mange chaque pomme, score final 429, une seule victoire", () => {
  let body = [path[2], path[1], path[0]], score = 0, wins = 0, food = SNK.pickFood(body, COLS, ROWS, () => 0.99), guard = 0;
  // la nourriture est placée en suivant le parcours pour que le serpent la rencontre : on prend la prochaine case libre du parcours
  food = path[3];
  for (let i = 3; i < path.length && guard++ < 1000; i++) {
    const head = path[i];
    assert.deepEqual(head, food, "le serpent mange la pomme");
    body.unshift(head); score++;
    food = SNK.pickFood(body, COLS, ROWS, () => 0);                      // doit toujours rendre une case libre ou null
    if (!food) { wins++; break; }
    food = path[i + 1];                                                  // la partie reprend sur la case suivante du parcours
    assert.ok(!body.some((b) => b.x === food.x && b.y === food.y));
  }
  assert.equal(score, 429); assert.equal(wins, 1); assert.equal(body.length, COLS * ROWS);
});
t("le jeu réel : victoire distincte (état, écran, boutons REJOUER / ACCUEIL), fin unique, points d'accroche présents", () => {
  assert.match(src, /function win\(\) \{\s*if \(won \|\| state === "over"\) return;/);
  assert.match(src, /won \? \["VICTOIRE !", "GRILLE COMPLETE"/);
  assert.match(src, /new CustomEvent\("boygames:victory"/);
  assert.match(src, /id="snake-hero"/);
  assert.match(src, /el\("button", "btn", "REJOUER"\)[\s\S]*el\("button", "btn alt", "ACCUEIL"\)/);
  assert.match(src, /function finish\(\) \{\s*if \(state === "over"\) return;/);
});
console.log(n + " tests OK");

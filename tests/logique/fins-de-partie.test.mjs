// Fin de partie unique dans chaque jeu solo : un second appel à finish() ne renvoie jamais le score (lecture de src/app-fragment.html).
import assert from "node:assert/strict";
import fs from "node:fs";
const src = fs.readFileSync(new URL("../../src/app-fragment.html", import.meta.url), "utf8");
let n = 0; const t = (name, fn) => { fn(); n++; console.log("  ok", name); };
const game = (start, end) => src.slice(src.indexOf(start), end ? src.indexOf(end, src.indexOf(start)) : undefined);
const snake = game("var snake = (function", "var blocks = (function"), blocks = game("var blocks = (function", "function makeBoyBlocks("), boyblocks = game("function makeBoyBlocks(", "var boyblocks = makeBoyBlocks(");

t("Snake : fin unique, victoire unique", () => {
  assert.match(snake, /function finish\(\) \{\s*if \(state === "over"\) return;/);
  assert.match(snake, /function win\(\) \{\s*if \(won \|\| state === "over"\) return;/);
});
t("Block Drop : fin unique", () => {
  assert.match(blocks, /function finish\(\) \{\s*if \(state === "over"\) return;/);
});
t("BoyBlocks : fin unique, et la grille de départ bloquée se termine quand même une fois", () => {
  assert.match(boyblocks, /async function finish\(\) \{\s*if \(state === "over"\) return;/);
  assert.doesNotMatch(boyblocks, /state = g\.over \? "over" : "playing";\s*if \(g\.over\) finish\(\);/);
  assert.match(boyblocks, /state = "playing";\s*if \(g\.over\) finish\(\);/);
});
console.log(n + " tests OK");

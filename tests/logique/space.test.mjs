// Logique de Space Attack (solo) : extraite de src/app-fragment.html entre les marqueurs SPACE-LOGIC.
import assert from "node:assert/strict";
import fs from "node:fs";
const src = fs.readFileSync(new URL("../../src/app-fragment.html", import.meta.url), "utf8");
const code = src.slice(src.indexOf("/*SPACE-LOGIC-START*/"), src.indexOf("/*SPACE-LOGIC-END*/"));
const SP = new Function(code + "\nreturn SP;")();
let n = 0; const t = (name, fn) => { fn(); n++; console.log("  ok", name); };
const seq = (vals) => { let i = 0; return () => vals[i++ % vals.length]; };
const run = (g, ms, x, rand = seq([0.5])) => { for (let k = 0; k < ms / 16; k++) SP.step(g, 0.016, { targetX: x }, rand); };

t("horde 1 éliminée : pas de bonus ; horde 2 : un bonus tombe", () => {
  const g = SP.create(); g.enemies = []; run(g, 16, 70);
  assert.equal(g.wave, 2); assert.equal(g.drops.length, 0);
  g.enemies = []; run(g, 16, 70);
  assert.equal(g.wave, 3); assert.equal(g.drops.length, 1);
});
t("un bonus ramassé par le vaisseau s'active ; raté, il disparaît", () => {
  const g = SP.create(); g.enemies = [{ x: 10, y: 30, row: 0 }]; g.dir = 0; g.enemyFireAt = 1e9;
  g.drops.push({ kind: "triple", x: g.ship.x + 2, y: SP.SHIP_Y - 12 }); run(g, 600, null);
  assert.ok(g.power.triple > 0); assert.equal(g.drops.length, 0);
  g.drops.push({ kind: "rapid", x: 0, y: SP.SHIP_Y - 4 }); g.ship.x = 120; run(g, 1500, 126);
  assert.equal(g.power.rapid, 0); assert.equal(g.drops.length, 0);
});
t("triple tir : trois balles par salve ; tir rapide : cadence doublée", () => {
  const g = SP.create(); g.enemies = [{ x: 10, y: 30, row: 0 }]; g.dir = 0; g.enemyFireAt = 1e9; g.power.triple = 5000;
  SP.step(g, 0.016, { targetX: 70 }, seq([0.5])); assert.equal(g.bullets.length, 3);
  const a = SP.create(); a.enemies = [{ x: 10, y: 30, row: 0 }]; a.dir = 0; a.enemyFireAt = 1e9; run(a, 1000, 70); const normal = a.score + a.fireAt;
  const b = SP.create(); b.enemies = [{ x: 10, y: 30, row: 0 }]; b.dir = 0; b.enemyFireAt = 1e9; b.power.rapid = 5000;
  let shotsA = 0, shotsB = 0;
  for (let k = 0; k < 60; k++) { const la = a.bullets.length; SP.step(a, 0.016, { targetX: 70 }, seq([0.5])); if (a.bullets.length > la) shotsA++;
                                 const lb = b.bullets.length; SP.step(b, 0.016, { targetX: 70 }, seq([0.5])); if (b.bullets.length > lb) shotsB++; }
  assert.ok(shotsB >= shotsA * 2 - 1, `rapide ${shotsB} vs normal ${shotsA}`); void normal;
});
t("laser : traverse et détruit plusieurs ennemis alignés", () => {
  const g = SP.create(); g.enemyFireAt = 1e9; g.power.laser = 5000;
  const x = g.ship.x + SP.SHIP_W / 2 - 4; g.enemies = [{ x, y: 60, row: 0 }, { x, y: 80, row: 1 }, { x: 10, y: 30, row: 0 }]; g.dir = 0;
  run(g, 1000, g.ship.x + SP.SHIP_W / 2);
  assert.ok(g.enemies.length <= 1, "il reste " + g.enemies.length);
});
t("bouclier : absorbe un tir, puis disparaît", () => {
  const g = SP.create(); g.enemies = [{ x: 10, y: 30, row: 0 }]; g.dir = 0; g.enemyFireAt = 1e9; g.power.shield = 5000;
  g.shots.push({ x: g.ship.x + 5, y: SP.SHIP_Y - 2 }); run(g, 100, null);
  assert.equal(g.lives, 3); assert.equal(g.power.shield, 0);
});
t("vie : +1 jusqu'à 5, ensuite 250 points", () => {
  const g = SP.create(); SP.applyBonus(g, "life"); SP.applyBonus(g, "life"); SP.applyBonus(g, "life");
  assert.equal(g.lives, 5); assert.equal(g.score, 250);
});
t("les bonus temporaires expirent", () => {
  const g = SP.create(); g.enemies = [{ x: 10, y: 30, row: 0 }]; g.dir = 0; g.enemyFireAt = 1e9;
  SP.applyBonus(g, "laser"); run(g, SP.BONUS.laser.ms + 200, 70); assert.equal(g.power.laser, 0);
});
t("partie normale jusqu'au bout sans erreur", () => {
  let s = 7; const r = () => (s = (s * 1664525 + 1013904223) >>> 0) / 4294967296;
  const g = SP.create(); let k = 0;
  while (!g.over && k++ < 60000) SP.step(g, 0.016, { targetX: 72 + 50 * Math.sin(k / 40) }, r);
  assert.ok(g.over || k >= 60000); assert.ok(g.score >= 0);
});
t("le jeu réel : fin unique, aucun score tronqué ni plafonné à 100 000, limite technique 2^53-1 seulement", () => {
  const space = src.slice(src.indexOf("var space = (function"), src.indexOf("/*SPACE-LOGIC-START*/") > src.indexOf("var space = (function") ? src.indexOf("/*SPACE-LOGIC-START*/") : undefined);
  assert.match(space, /function finish\(\) \{\s*if \(state === "over"\) return;/);
  assert.doesNotMatch(src, /Math\.min\([^)]*100000\)/);
  assert.match(src, /var SPACE_SCORE_MAX = 9007199254740991;/);
  assert.equal(9007199254740991, Number.MAX_SAFE_INTEGER);
  assert.match(space, /submitRanked\("space", value\)/);
});
t("score très élevé (227 500 puis 50 000 000) : le moteur continue de compter, entier exact, jamais ramené à 100 000", () => {
  for (const start of [227_500, 50_000_000]) {
    const g = SP.create(); g.score = start;
    for (let w = 0; w < 200; w++) { g.enemies = []; SP.step(g, 0.016, { targetX: 70 }, seq([0.5])); }
    assert.ok(Number.isSafeInteger(g.score) && g.score >= start, String(g.score));
  }
});
console.log(n + " tests OK");

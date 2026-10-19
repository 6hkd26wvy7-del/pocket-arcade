import assert from "node:assert/strict";
import { createRequire } from "node:module";
const P = createRequire(import.meta.url)("./pulse-logic.js");
let n = 0; const t = (name, fn) => { fn(); n++; console.log("ok -", name); };
const quiet = (seed) => { const g = P.newGame(seed); g.nextSpawn = 1e9; return g; };   // pas d'apparition automatique
const orb = (g, kind, d, v = 0) => { const o = { kind, hp: kind === "tough" ? 2 : 1, ang: 0, d, v }; g.orbs.push(o); return o; };
const run = (g, s) => { for (let i = 0; i < Math.round(s * 60); i++) P.step(g, 1 / 60); };

t("même graine = même partie", () => {
  const a = P.newGame(7), b = P.newGame(7); run(a, 20); run(b, 20);
  assert.deepEqual(a.orbs.map((o) => [o.kind, o.d.toFixed(3)]), b.orbs.map((o) => [o.kind, o.d.toFixed(3)]));
});
t("une onde détruit l'orbe qu'elle traverse (+10)", () => {
  const g = quiet(1); orb(g, "std", 150); assert.ok(P.pulse(g)); run(g, 0.5);
  assert.equal(g.orbs.length, 0); assert.equal(g.score, 10); assert.equal(g.lives, 3);
});
t("l'onde n'atteint pas un orbe hors de portée avant qu'il ne bouge", () => {
  const g = quiet(1); orb(g, "std", 290); P.pulse(g); run(g, 0.2); assert.equal(g.orbs.length, 1);
});
t("un orbe violet demande deux ondes", () => {
  const g = quiet(1); const o = orb(g, "tough", 200); P.pulse(g); run(g, 0.7); assert.equal(g.orbs.length, 1); assert.equal(o.hp, 1);
  P.pulse(g); run(g, 0.7); assert.equal(g.orbs.length, 0); assert.equal(g.score, 10);
});
t("toucher une bombe coûte une vie, sans points", () => {
  const g = quiet(1); orb(g, "bomb", 150); P.pulse(g); run(g, 0.5); assert.equal(g.lives, 2); assert.equal(g.score, 0); assert.equal(g.orbs.length, 0);
});
t("une bombe qui arrive au centre s'éteint sans dégât", () => {
  const g = quiet(1); orb(g, "bomb", 40, 100); run(g, 0.5); assert.equal(g.lives, 3); assert.equal(g.orbs.length, 0);
});
t("un orbe qui atteint le noyau coûte une vie", () => {
  const g = quiet(1); orb(g, "std", 40, 100); run(g, 0.5); assert.equal(g.lives, 2);
});
t("trois vies perdues = fin de partie, plus aucune action", () => {
  const g = quiet(1); for (let i = 0; i < 3; i++) orb(g, "std", 25, 100); run(g, 0.5);
  assert.ok(g.over); assert.equal(g.lives, 0); assert.equal(P.pulse(g), false);
});
t("énergie : 3 charges, une par onde, recharge progressive", () => {
  const g = quiet(1); assert.ok(P.pulse(g) && P.pulse(g) && P.pulse(g)); assert.equal(P.pulse(g), false);
  run(g, 1.2); assert.ok(P.pulse(g)); assert.equal(P.pulse(g), false);
  const h = quiet(2); run(h, 30); assert.ok(h.energy <= P.ENERGY_MAX);
});
t("combo : 3 orbes avec la même onde = 30 + 60 de bonus", () => {
  const g = quiet(1); orb(g, "std", 100); orb(g, "std", 150); orb(g, "std", 200); P.pulse(g); run(g, 0.9);
  assert.equal(g.score, 30 + 60);
});
t("une onde ne touche pas deux fois le même orbe violet", () => {
  const g = quiet(1); const o = orb(g, "tough", 200); P.pulse(g); run(g, 1.2); assert.equal(o.hp, 1);
});
t("la difficulté monte sans devenir injouable", () => {
  assert.ok(P.spawnDelay(0) > P.spawnDelay(60)); assert.ok(P.spawnDelay(1e6) >= 0.35); assert.ok(P.orbSpeed(1e6) <= 78);
});
t("bot raisonnable : tapoter régulièrement dure plus que ne rien faire", () => {
  const idle = P.newGame(3); run(idle, 60);
  const bot = P.newGame(3); for (let i = 0; i < 3600; i++) { if (i % 48 === 0) P.pulse(bot); P.step(bot, 1 / 60); }
  assert.ok(idle.over, "sans action on perd"); assert.ok(bot.score > 0);
});
console.log(n + " tests OK");

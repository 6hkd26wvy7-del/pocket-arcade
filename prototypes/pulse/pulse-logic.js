/* PULSE — logique pure du prototype (aucun accès réseau, aucun score envoyé, aucune récompense).
   Un noyau au centre, des orbes arrivent des bords. Un tap lance une onde ; elle détruit les orbes qu'elle traverse.
   Orbes cyan : 1 onde. Orbes violets : 2 ondes. Bombes corail : ne PAS les toucher (elles s'éteignent seules au centre). */
(function (root) {
  var R = 300;                 // rayon de l'arène
  var CORE = 22;               // rayon du noyau (un orbe qui l'atteint coûte une vie)
  var WAVE_SPEED = 520;        // vitesse de l'onde (unités / s)
  var ENERGY_MAX = 3, ENERGY_REGEN = 1 / 1.1;   // 1 charge toutes les ~1,1 s
  var LIVES = 3;

  function rng(seed) {         // mulberry32
    var a = seed >>> 0;
    return function () { a |= 0; a = (a + 0x6D2B79F5) | 0; var t = Math.imul(a ^ (a >>> 15), 1 | a); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
  }
  function newGame(seed) {
    return { rand: rng(seed), t: 0, over: false, score: 0, lives: LIVES, energy: ENERGY_MAX, orbs: [], waves: [], nextSpawn: 0.8, best: 0, events: [] };
  }
  function spawnDelay(t) { return Math.max(0.35, 1.1 - t * 0.012); }
  function orbSpeed(t) { return 38 + Math.min(40, t * 0.5); }
  function spawn(g) {
    var r = g.rand(), kind = r < 0.18 ? "bomb" : r < 0.40 ? "tough" : "std";
    var ang = g.rand() * Math.PI * 2;
    g.orbs.push({ kind: kind, hp: kind === "tough" ? 2 : 1, ang: ang, d: R, v: orbSpeed(g.t) * (kind === "bomb" ? 0.9 : 1) });
  }
  function pulse(g) {          // retourne true si une onde est partie
    if (g.over || g.energy < 1) return false;
    g.energy -= 1; g.waves.push({ r: 0, hit: 0 }); return true;
  }
  function loseLife(g) { g.lives--; g.events.push("life"); if (g.lives <= 0) { g.lives = 0; g.over = true; } }
  function step(g, dt) {
    if (g.over) return g;
    g.events = []; g.t += dt;
    g.energy = Math.min(ENERGY_MAX, g.energy + ENERGY_REGEN * dt);
    g.nextSpawn -= dt;
    while (g.nextSpawn <= 0) { spawn(g); g.nextSpawn += spawnDelay(g.t); }
    var i, j, o, w;
    for (i = 0; i < g.waves.length; i++) {
      w = g.waves[i]; var prev = w.r; w.r += WAVE_SPEED * dt;
      for (j = 0; j < g.orbs.length; j++) {
        o = g.orbs[j];
        if (o.dead || o.d <= prev || o.d > w.r || o.lastWave === w) continue;
        o.lastWave = w;
        if (o.kind === "bomb") { o.dead = true; g.events.push("bomb"); loseLife(g); continue; }
        o.hp--; if (o.hp <= 0) { o.dead = true; w.hit++; g.events.push("pop"); } else g.events.push("crack");
      }
    }
    g.waves = g.waves.filter(function (x) { if (x.r < R) return true; if (x.hit > 1) { g.score += 10 * x.hit * (x.hit + 1) / 2; g.events.push("combo"); } return false; });
    for (i = 0; i < g.orbs.length; i++) {
      o = g.orbs[i]; if (o.dead) continue;
      o.d -= o.v * dt;
      if (o.d <= CORE) { o.dead = true; if (o.kind !== "bomb") loseLife(g); }
    }
    // points simples : 10 par orbe détruit seul (le bonus de combo s'ajoute à la fin de l'onde)
    var popped = 0; g.orbs.forEach(function (x) { if (x.dead && !x.counted) { x.counted = true; if (x.hp <= 0 && x.kind !== "bomb") popped++; } });
    g.score += popped * 10;
    g.orbs = g.orbs.filter(function (x) { return !x.dead; });
    return g;
  }
  var api = { R: R, CORE: CORE, WAVE_SPEED: WAVE_SPEED, ENERGY_MAX: ENERGY_MAX, LIVES: LIVES, newGame: newGame, step: step, pulse: pulse, spawnDelay: spawnDelay, orbSpeed: orbSpeed };
  if (typeof module !== "undefined" && module.exports) module.exports = api; else root.PULSE = api;
})(typeof window !== "undefined" ? window : globalThis);

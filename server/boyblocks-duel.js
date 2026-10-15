// BOYBLOCKS en duel : même grille et mêmes pièces pour les deux joueurs, 2 minutes, le meilleur score gagne.
// Le serveur rejoue et valide chaque coup avec le moteur partagé : le téléphone ne peut pas tricher sur son score.
import * as BB from "./boyblocks-engine.js";

export const TICK_MS = 250;
export const DURATION_MS = 120000;
const MIN_MOVE_MS = 150; // un humain ne pose pas plus de ~6 pièces par seconde

export function newGame(seed) {
  const s = seed >>> 0;
  return {
    seed: s, ms: 0, over: false, winner: null, reason: null,
    // ensureFit=false : aucun joueur n'est avantagé par des pièces "arrangées" selon sa grille
    players: [BB.newGame(s, { ensureFit: false }), BB.newGame(s, { ensureFit: false })],
  };
}

function leader(g) {
  const a = g.players[0].score, b = g.players[1].score;
  return a === b ? "draw" : a > b ? 0 : 1;
}

function checkEnd(g) {
  if (g.over) return;
  const [a, b] = g.players;
  let reason = null;
  if (g.ms >= DURATION_MS) reason = "time";
  else if (a.over && b.over) reason = "blocked";
  else if (a.over && b.score > a.score) reason = "blocked";
  else if (b.over && a.score > b.score) reason = "blocked";
  if (reason) { g.over = true; g.reason = reason; g.winner = leader(g); }
}

// Retourne true si le coup a été accepté.
export function input(g, i, m) {
  if (g.over || !m || m.t !== "place") return false;
  const p = g.players[i];
  if (!p || p.over) return false;
  if (!Number.isInteger(m.slot) || !Number.isInteger(m.r) || !Number.isInteger(m.c)) return false;
  if (p.moves >= 4 + g.ms / MIN_MOVE_MS) return false;     // trop rapide
  const res = BB.place(p, m.slot, m.r, m.c);
  if (!res.ok) return false;
  checkEnd(g);
  return true;
}

export function step(g, dt) {
  if (g.over) return;
  g.ms += dt;
  checkEnd(g);
}

export function syncLog(g, i) { return { t: "sync", seed: g.seed, log: g.players[i].log.slice() }; }

export function snapshot(g) {
  return {
    t: "state", kind: "boyblocks", over: g.over, winner: g.winner, reason: g.reason,
    seed: g.seed, msLeft: Math.max(0, DURATION_MS - g.ms), total: DURATION_MS,
    players: g.players.map((p) => ({
      score: p.score, lines: p.lines, streak: p.streak, moves: p.moves, blocked: p.over,
      grid: p.grid.join(""), // 64 chiffres 0-7
    })),
  };
}

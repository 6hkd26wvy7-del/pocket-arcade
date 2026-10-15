// Musique chiptune générée par le code (aucun morceau extérieur : aucun problème de droits sur les réseaux).
// Chaque graine donne une mélodie différente (gamme, tempo, motif) pour éviter des vidéos qui se ressemblent.
import fs from "node:fs";

function rng(seed) { let a = seed >>> 0; return () => { a = (a + 0x6D2B79F5) >>> 0; let t = a; t = Math.imul(t ^ (t >>> 15), t | 1); t ^= t + Math.imul(t ^ (t >>> 7), t | 61); return ((t ^ (t >>> 14)) >>> 0) / 4294967296; }; }

export function musique(fichier, { secondes = 30, graine = 1 } = {}) {
  const R = rng(graine), SR = 44100, n = Math.floor(secondes * SR), buf = new Float32Array(n);
  const GAMMES = [[0, 2, 4, 7, 9], [0, 3, 5, 7, 10], [0, 2, 3, 7, 8], [0, 4, 7, 9, 11]];
  const gamme = GAMMES[Math.floor(R() * GAMMES.length)], base = 220 * Math.pow(2, Math.floor(R() * 5) / 12);
  const bpm = 120 + Math.floor(R() * 40), pas = 60 / bpm / 2;                     // croches
  const motif = Array.from({ length: 16 }, () => (R() < 0.8 ? gamme[Math.floor(R() * gamme.length)] + 12 * Math.floor(R() * 2) : null));
  const basse = [0, 0, gamme[3] - 12, gamme[2] - 12];
  const freq = (demi) => base * Math.pow(2, demi / 12);
  const carre = (t, f, rapport = 0.5) => ((t * f) % 1 < rapport ? 1 : -1);
  for (let i = 0; i < n; i++) {
    const t = i / SR, k = Math.floor(t / pas), dans = (t % pas) / pas;
    let v = 0;
    const note = motif[k % 16];
    if (note !== null) v += 0.16 * carre(t, freq(note), 0.25) * Math.max(0, 1 - dans * 1.4);         // mélodie
    v += 0.13 * carre(t, freq(basse[Math.floor(k / 8) % 4] - 12)) * (dans < 0.85 ? 1 : 0);           // basse
    if (k % 4 === 0) v += 0.22 * (R() * 2 - 1) * Math.max(0, 1 - dans * 6);                          // percussion (bruit)
    if (k % 2 === 1) v += 0.06 * (R() * 2 - 1) * Math.max(0, 1 - dans * 12);                         // charleston
    const fondu = Math.min(1, t / 0.4, (secondes - t) / 1.2);
    buf[i] = Math.max(-1, Math.min(1, v * fondu));
  }
  const data = Buffer.alloc(n * 2);
  for (let i = 0; i < n; i++) data.writeInt16LE(Math.round(buf[i] * 30000), i * 2);
  const h = Buffer.alloc(44);
  h.write("RIFF", 0); h.writeUInt32LE(36 + data.length, 4); h.write("WAVE", 8); h.write("fmt ", 12);
  h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22); h.writeUInt32LE(SR, 24); h.writeUInt32LE(SR * 2, 28);
  h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34); h.write("data", 36); h.writeUInt32LE(data.length, 40);
  fs.writeFileSync(fichier, Buffer.concat([h, data]));
  return { bpm, gamme };
}

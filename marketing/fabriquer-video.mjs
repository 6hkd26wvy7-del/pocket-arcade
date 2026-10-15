// Fabrique une vidéo verticale 9:16 à partir d'une vraie partie : capture, textes, musique, montage.
// Usage : node fabriquer-video.mjs [graine]      Sortie : marketing/sortie/<date-graine>/video.mp4 + infos.json
// Ne publie rien : la publication passe par la file de validation (voir docs/MARKETING.md).
import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import ffmpegStatic from "ffmpeg-static";
const ffmpeg = process.env.FFMPEG || ffmpegStatic;          // dans le cloud : ffmpeg du système
import { choisirPartie, capturer } from "./capturer.mjs";
import { ecrireTextes } from "./textes.mjs";
import { musique } from "./musique.mjs";

const HERE = path.dirname(new URL(import.meta.url).pathname);
const graine = Number(process.argv[2] || Date.now() % 100000);
const DUREE_MAX = 28;                                         // secondes : format court, regardé jusqu'au bout
const POLICE = ["/System/Library/Fonts/Supplemental/Arial Black.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"].find((f) => fs.existsSync(f));

const dossier = path.join(HERE, "sortie", new Date().toISOString().slice(0, 10) + "-" + graine);
fs.mkdirSync(dossier, { recursive: true });
const historiquePath = path.join(HERE, "sortie", "historique.json");
const historique = fs.existsSync(historiquePath) ? JSON.parse(fs.readFileSync(historiquePath, "utf8")) : [];

console.log("1/4 choix d'une belle partie…");
const choix = choisirPartie(graine * 1009);
console.log("2/4 capture de la partie (graine " + choix.seed + ")…");
const cap = await capturer({ seed: choix.seed, dossier });
console.log("3/4 textes…");
const textes = await ecrireTextes(cap, { historique: historique.map((h) => h.accroche), graine });
const brut = cap.fin - cap.debut, vitesse = Math.max(1, brut / DUREE_MAX), duree = brut / vitesse;
musique(path.join(dossier, "musique.wav"), { secondes: Math.ceil(duree) + 1, graine });

console.log("4/4 montage…");
const tf = (nom, txt) => { const f = path.join(dossier, nom); fs.writeFileSync(f, txt); return f.replace(/:/g, "\\:"); };
const police = POLICE.replace(/:/g, "\\:");
const filtres = [
  `[0:v]trim=start=${cap.debut.toFixed(2)}:end=${cap.fin.toFixed(2)},setpts=(PTS-STARTPTS)/${vitesse.toFixed(3)},fps=30,scale=1080:1920,format=yuv420p[v0]`,
  // accroche en haut pendant les 3 premières secondes
  `[v0]drawtext=fontfile='${police}':textfile='${tf("accroche.txt", textes.accroche)}':fontsize=70:fontcolor=white:borderw=6:bordercolor=0x0F172A:` +
    `box=1:boxcolor=0x7C3AED@0.85:boxborderw=28:x=(w-text_w)/2:y=1700:enable='lt(t,3.2)'[v1]`,
];
// « COMBO » aux vrais moments où des lignes s'effacent
let cur = "v1";
cap.moments.filter((m) => m.combo >= 2 || m.lignes >= 2).slice(0, 6).forEach((m, i) => {
  const t = (m.t - cap.debut) / vitesse;
  const label = m.combo >= 2 ? `COMBO x${m.combo} !` : `${m.lignes} LIGNES !`;
  filtres.push(`[${cur}]drawtext=fontfile='${police}':textfile='${tf("combo" + i + ".txt", label)}':fontsize=84:fontcolor=0xFDE68A:borderw=7:bordercolor=0x0F172A:` +
    `x=(w-text_w)/2:y=1500:enable='between(t,${t.toFixed(2)},${(t + 0.9).toFixed(2)})'[c${i}]`);
  cur = "c" + i;
});
// fin : appel à l'action
const fin0 = Math.max(0, duree - 3).toFixed(2);
filtres.push(`[${cur}]drawbox=x=0:y=0:w=iw:h=ih:color=0x0F172A@0.78:t=fill:enable='gte(t,${fin0})',` +
  `drawtext=fontfile='${police}':textfile='${tf("cta1.txt", "BOYGAMES")}':fontsize=130:fontcolor=white:x=(w-text_w)/2:y=760:enable='gte(t,${fin0})',` +
  `drawtext=fontfile='${police}':textfile='${tf("cta2.txt", "Joue gratuitement")}':fontsize=64:fontcolor=0x22D3EE:x=(w-text_w)/2:y=940:enable='gte(t,${fin0})',` +
  `drawtext=fontfile='${police}':textfile='${tf("cta3.txt", "Lien dans la bio")}':fontsize=52:fontcolor=0xFDE68A:x=(w-text_w)/2:y=1040:enable='gte(t,${fin0})'[vout]`);
execFileSync(ffmpeg, ["-y", "-hide_banner", "-loglevel", "error", ...(cap.concat ? ["-f", "concat", "-safe", "0"] : []), "-i", cap.video, "-i", path.join(dossier, "musique.wav"),
  "-filter_complex", filtres.join(";"), "-map", "[vout]", "-map", "1:a", "-t", duree.toFixed(2),
  "-c:v", "libx264", "-preset", "medium", "-crf", "21", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart",
  path.join(dossier, "video.mp4")]);
if (cap.imgDir) fs.rmSync(cap.imgDir, { recursive: true, force: true }); fs.rmSync(cap.video, { force: true });   // fichiers de travail du montage

const infos = { graine, seed: choix.seed, duree: Number(duree.toFixed(1)), partie: { score: cap.score, combo: cap.combo, lignes: cap.lignes, coups: cap.coups },
  textes, fichier: "video.mp4", cree_le: new Date().toISOString(), statut: "a_valider" };
fs.writeFileSync(path.join(dossier, "infos.json"), JSON.stringify(infos, null, 2));
historique.push({ accroche: textes.accroche, dossier: path.basename(dossier) });
fs.writeFileSync(historiquePath, JSON.stringify(historique, null, 2));
console.log("prêt :", path.join(dossier, "video.mp4"), "|", JSON.stringify(infos.partie), "|", textes.accroche, "|", textes.source);

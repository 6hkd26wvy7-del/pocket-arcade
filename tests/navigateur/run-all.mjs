// Lance tous les tests navigateur (faux Supabase, faux serveur de duel) et s'arrête au premier problème.
// Prérequis : npm install && npx playwright install chromium. Reconstruit d abord site/ et test/ depuis src/
import { execFileSync, spawnSync } from "child_process";
const ROOT = new URL("../../", import.meta.url).pathname, HERE = new URL("./", import.meta.url).pathname;
execFileSync("python3", ["-I", ROOT + "make_test_release.py"], { cwd: ROOT, stdio: "ignore" }); // reconstruit site/ et test/

// fichier -> textes qui doivent apparaître dans la sortie
const TESTS = {
  "bb.mjs": ["identiques: true", "Score vérifié et enregistré"],
  "duel.mjs": ["TU AS GAGNÉ", "rejouer visible: true"],
  "tiers.mjs": ["PALIER ARGENT", "PALIER LÉGENDE", "boyblocks:5"],
  "regress.mjs": ["boyblocks true"],
  "bug.js": ["Signalement n°42 envoyé", "panneau bugs: true", "ALLER AU PROFIL"],
  "ui.js": ["OFFRIR dans le chat ? false", "unblock_user", "set_avatar"],
  "ui3.js": ["Sauvegarde vérifiée et téléchargée"],
  "ui4.js": ["Sauvegarde vérifiée et téléchargée"],
  "iphone.mjs": ["envoyés identiques: true", "Score vérifié et enregistré", "protection ok"],
};
let bad = 0;
for (const [f, want] of Object.entries(TESTS)) {
  const r = spawnSync(process.execPath, [HERE + f], { cwd: HERE, encoding: "utf8", timeout: 180000 });
  const out = (r.stdout || "") + (r.stderr || "");
  const missing = want.filter((w) => !out.includes(w));
  const jsErrors = /(errors|erreurs JS:) \[(?!\])/.test(out);
  const ok = r.status === 0 && !missing.length && !jsErrors;
  console.log((ok ? "OK    " : "ECHEC ") + f + (missing.length ? "  manque : " + missing.join(" / ") : "") + (jsErrors ? "  erreurs JS dans la page" : ""));
  if (!ok) { bad++; console.log(out.split("\n").slice(-15).join("\n")); }
}
console.log(bad ? bad + " test(s) en échec" : "tous les tests navigateur OK");
process.exit(bad ? 1 : 0);

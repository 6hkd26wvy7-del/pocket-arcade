// Vérifie dist-preview/ (site TEST pour Cloudflare Pages) : aucune production, aucun secret, protections présentes.
// Usage : sh cloudflare/preparer-previsualisation.sh && node tests/preview/verifier-previsualisation.mjs
import fs from "node:fs";
import path from "node:path";
const D = "dist-preview", PROD = "rvygnqpagbmiqbdkwlfp", TEST = "xgoqwxvgiavajnygoblt";
const ORIGINE = "https://preview.boygames-preview.pages.dev";
let echecs = 0;
const ok = (c, m) => { console.log((c ? "OK    " : "ÉCHEC ") + m); if (!c) echecs++; };
const lire = (f) => fs.readFileSync(f, "utf8");
const fichiers = fs.readdirSync(D).map((f) => path.join(D, f)).filter((f) => fs.statSync(f).isFile());
const texte = fichiers.filter((f) => /\.(html|js|json|webmanifest|txt)$|_headers$/.test(f)).map(lire).join("\n");
ok(!texte.includes(PROD), "aucune référence à la base de production");
ok(texte.includes(TEST), "configuration Supabase TEST présente");
ok(!/service_role|sb_secret_|eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\./.test(texte), "aucune clé secrète ni jeton dans le site");
ok(!/dj-academy|djacademy/i.test(texte), "aucune référence à DJ Académie");
ok(/X-Robots-Tag: noindex/.test(lire(D + "/_headers")), "en-tête noindex");
ok(/X-Frame-Options: DENY/.test(lire(D + "/_headers")), "en-tête anti-intégration (X-Frame-Options)");
ok(/Disallow: \//.test(lire(D + "/robots.txt")), "robots.txt interdit l'indexation");
ok(!fs.existsSync(D + "/.env") && !fichiers.some((f) => /\.(pem|key)$/.test(f)), "aucun fichier .env ni clé privée");
const wr = lire("server/wrangler.toml");
const m = wr.match(/ALLOWED_ORIGINS\s*=\s*"([^"]*)"/);
const liste = m ? m[1].split(",").map((s) => s.trim()) : [];
ok(liste.includes(ORIGINE), "origine de prévisualisation autorisée pour les duels : " + ORIGINE);
ok(!liste.some((o) => o === "*" || o.endsWith(".pages.dev") && o !== ORIGINE), "pas de joker dans ALLOWED_ORIGINS");
const wf = lire(".github/workflows/previsualisation-test.yml");
ok(!/branches:\s*\[?\s*main/.test(wf) && /preview\/\*\*/.test(wf), "le workflow ne se déclenche que sur preview/**");
ok(/PREVIEW_ACCESS_CONFIRMED/.test(wf), "déploiement conditionné à la protection d'accès");
ok(!/DJ_|DJACADEMY/i.test(wf), "aucun secret DJ Académie dans le workflow");
ok(/environment:\s*boygames-preview/.test(wf), "secrets liés à l'environnement boygames-preview");
if (echecs) { console.log(echecs + " échec(s)"); process.exit(1); }
console.log("tout est conforme");

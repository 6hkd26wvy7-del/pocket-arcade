// Publicités AdSense (src/pub.js, src/reglages-pub.js, build.py) : rien d'actif sans approbation, consentement d'abord,
// jamais en partie, ads.txt seulement avec un vrai identifiant.
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const ROOT = new URL("../../", import.meta.url).pathname;
const P = require(ROOT + "src/pub.js");
let n = 0; const t = (name, fn) => { fn(); n++; console.log("  ok", name); };

const ID = "ca-pub-1234567890123456";
const ON = { enabled: true, approved: true, publisherId: ID, slots: { home: "1111111111", scores: "2222222222", shop: "" }, underAgeOfConsent: true };
const SRV = { enabled: true, provider: "adsense", slots: { home: true, scores: true, shop: true } };

t("réglages livrés : tout désactivé, aucun identifiant inventé", () => {
  const src = fs.readFileSync(ROOT + "src/reglages-pub.js", "utf8");
  const win = {}; new Function("window", src)(win);
  const c = win.BG_PUB_CONFIG;
  assert.equal(c.enabled, false); assert.equal(c.approved, false); assert.equal(c.publisherId, "");
  assert.deepEqual(Object.values(c.slots), ["", "", ""]); assert.equal(c.underAgeOfConsent, true);
  assert.equal(P.decide(c, SRV).active, false);
});
t("il faut les trois verrous : activé, approuvé par Google, identifiant valide", () => {
  assert.equal(P.decide(ON, SRV).active, true);
  assert.match(P.decide({ ...ON, enabled: false }, SRV).reason, /désactivé/);
  assert.match(P.decide({ ...ON, approved: false }, SRV).reason, /approuvé/);
  assert.match(P.decide({ ...ON, approved: "true" }, SRV).reason, /approuvé/);
  for (const bad of ["", "pub-1234567890123456", "ca-pub-123", "ca-pub-XXXXXXXXXXXXXXXX"]) assert.equal(P.decide({ ...ON, publisherId: bad }, SRV).active, false);
});
t("le réglage serveur doit aussi l'autoriser (régie adsense) ; jamais pour un Premium", () => {
  assert.equal(P.decide(ON, null).active, false);
  assert.equal(P.decide(ON, { ...SRV, enabled: false }).active, false);
  assert.equal(P.decide(ON, { ...SRV, provider: "test" }).active, false);
  assert.equal(P.decide(ON, SRV, { premium: true }).active, false);
});
t("emplacements : seulement accueil, classements, boutique, cochés et renseignés", () => {
  assert.deepEqual(Object.keys(P.PLACES).sort(), ["home", "scores", "shop"]);
  assert.equal(P.slotAllowed(ON, SRV, "home"), true);
  assert.equal(P.slotAllowed(ON, SRV, "shop"), false);                 // bloc d'annonces non renseigné
  assert.equal(P.slotAllowed(ON, { ...SRV, slots: { home: false } }, "home"), false);
  for (const g of ["snake", "space", "boyblocks", "blocks", "arena", "duel"]) assert.equal(P.slotAllowed({ ...ON, slots: { [g]: "1111111111" } }, { ...SRV, slots: { [g]: true } }, g), false);
});
t("consentement TCF : attendre le choix, refuser sans finalité 1, hors RGPD autorisé", () => {
  assert.equal(P.tcfAllows(null), null);
  assert.equal(P.tcfAllows({ gdprApplies: true, eventStatus: "cmpuishown", purpose: { consents: { 1: true } } }), null);
  assert.equal(P.tcfAllows({ gdprApplies: true, eventStatus: "useractioncomplete", purpose: { consents: {} } }), false);
  assert.equal(P.tcfAllows({ gdprApplies: true, eventStatus: "useractioncomplete", purpose: { consents: { 1: true } } }), true);
  assert.equal(P.tcfAllows({ gdprApplies: true, eventStatus: "tcloaded", purpose: { consents: { 1: true } } }), true);
  assert.equal(P.tcfAllows({ gdprApplies: false }), true);
});
t("ligne ads.txt : format Google, rien sans identifiant valide", () => {
  assert.equal(P.adsTxtLine(ID), "google.com, pub-1234567890123456, DIRECT, f08c47fec0942fa0");
  assert.equal(P.adsTxtLine(""), null); assert.equal(P.adsTxtLine("ca-pub-XXXX"), null);
});
t("build.py : pas d'ads.txt sans identifiant ; ads.txt écrit avec un identifiant (copie temporaire)", () => {
  const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "pub-"));
  for (const d of ["src", "shared", "design/badges", "sql"]) fs.mkdirSync(path.join(tmp, d), { recursive: true });
  for (const f of fs.readdirSync(ROOT + "src")) fs.copyFileSync(ROOT + "src/" + f, path.join(tmp, "src", f));
  for (const f of ["build.py", "README.md", "shared/boyblocks-engine.js", "design/badges/badges.js", "sql/schema_all.sql"]) fs.copyFileSync(ROOT + f, path.join(tmp, f));
  execFileSync("python3", ["-I", path.join(tmp, "build.py")], { cwd: tmp, stdio: "ignore" });
  assert.equal(fs.existsSync(path.join(tmp, "site/ads.txt")), false);
  assert.ok(fs.existsSync(path.join(tmp, "site/pub.js")) && fs.existsSync(path.join(tmp, "site/mentions-legales.html")));
  const rp = path.join(tmp, "src/reglages-pub.js");
  fs.writeFileSync(rp, fs.readFileSync(rp, "utf8").replace('publisherId: ""', 'publisherId: "' + ID + '"'));
  execFileSync("python3", ["-I", path.join(tmp, "build.py")], { cwd: tmp, stdio: "ignore" });
  assert.equal(fs.readFileSync(path.join(tmp, "site/ads.txt"), "utf8"), "google.com, pub-1234567890123456, DIRECT, f08c47fec0942fa0\n");
  fs.rmSync(tmp, { recursive: true, force: true });
});
t("pages légales : mentions liées partout, publicité décrite, plus de « pas de publicité »", () => {
  const app = fs.readFileSync(ROOT + "src/app-fragment.html", "utf8"), priv = fs.readFileSync(ROOT + "src/privacy.html", "utf8");
  assert.ok(app.includes('href="mentions-legales.html"') && app.includes('id="pub-consent"'));
  assert.ok(/AdSense/.test(priv) && /CNIL/.test(priv) && /moins de 15 ans/.test(priv) && /Gérer les cookies/.test(priv));
  assert.ok(!/ne les utilisons pas pour de la publicité/.test(priv));
  for (const f of ["privacy.html", "cgu.html"]) assert.ok(fs.readFileSync(ROOT + "src/" + f, "utf8").includes("mentions-legales.html"), f);
  // aucun emplacement de pub dans les écrans de jeu ou de duel
  for (const v of ["arena", "blocks", "boyblocks", "space", "snake"]) {
    const i = app.indexOf('<section id="view-' + v + '"'), j = app.indexOf("</section>", i);
    assert.ok(i > 0 && !app.slice(i, j).includes("ad-slot"), v);
  }
});
console.log(n + " tests publicité OK");

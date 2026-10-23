/* Publicités Google AdSense de BOYGAMES : décision, consentement et affichage.
   Règles (docs/ADSENSE.md) :
   - rien n'est chargé tant que reglages-pub.js (enabled + approved + identifiant valide) ET le réglage serveur
     (provider « adsense », emplacement coché) ne l'autorisent pas, ni pour un joueur Premium ;
   - jamais pendant une partie ou un duel : seuls les emplacements de l'accueil, des classements et de la boutique
     existent, et rien ne s'affiche quand le corps de la page porte la classe « ingame » ;
   - consentement d'abord : le bandeau de Google (Privacy & messaging, CMP certifiée TCF) est chargé, et le script
     d'annonces n'est chargé qu'après un choix de l'utilisateur qui autorise le stockage (finalité 1 du TCF) ;
   - annonces non personnalisées pour tous (data-tag-for-under-age-of-consent) tant que underAgeOfConsent vaut true. */
(function (root) {
  "use strict";

  var PUB_RE = /^ca-pub-\d{16}$/, SLOT_RE = /^\d{6,}$/;
  var PLACES = { home: "view-menu", scores: "view-scores", shop: "view-boutique" };   // emplacement -> seul écran permis
  var CMP_TIMEOUT = 15000;

  // Décision pure (testée sans navigateur) : la page peut-elle charger le code publicitaire ?
  function decide(cfg, ads, ctx) {
    ctx = ctx || {};
    if (!cfg || cfg.enabled !== true) return { active: false, reason: "désactivé dans reglages-pub.js" };
    if (cfg.approved !== true) return { active: false, reason: "site pas encore approuvé par Google" };
    if (!PUB_RE.test(String(cfg.publisherId || ""))) return { active: false, reason: "identifiant éditeur absent ou invalide" };
    if (!ads || ads.enabled !== true || ads.provider !== "adsense") return { active: false, reason: "publicités AdSense désactivées côté serveur" };
    if (ctx.premium) return { active: false, reason: "joueur Premium" };
    return { active: true, reason: "" };
  }
  // Un emplacement peut-il recevoir une annonce ? (nom connu, coché côté serveur, bloc d'annonces renseigné)
  function slotAllowed(cfg, ads, name) {
    return Object.prototype.hasOwnProperty.call(PLACES, name) && !!(ads && ads.slots && ads.slots[name]) &&
      SLOT_RE.test(String((cfg && cfg.slots && cfg.slots[name]) || ""));
  }
  // Décision TCF : true = le script d'annonces peut être chargé, false = refus, null = pas encore de choix.
  function tcfAllows(tc) {
    if (!tc) return null;
    if (tc.gdprApplies === false) return true;
    if (tc.eventStatus !== "tcloaded" && tc.eventStatus !== "useractioncomplete") return null;
    return !!(tc.purpose && tc.purpose.consents && tc.purpose.consents[1]);
  }
  function adsTxtLine(publisherId) {
    if (!PUB_RE.test(String(publisherId || ""))) return null;
    return "google.com, " + publisherId.replace(/^ca-/, "") + ", DIRECT, f08c47fec0942fa0";
  }

  var api = { decide: decide, slotAllowed: slotAllowed, tcfAllows: tcfAllows, adsTxtLine: adsTxtLine, PLACES: PLACES };

  if (typeof document === "undefined") { if (typeof module !== "undefined") module.exports = api; return; }

  // ---- Navigateur ----
  var state = { cmp: false, consent: null, script: false, ads: null, premium: false };

  function cfg() { return root.BG_PUB_CONFIG || null; }
  function addScript(src, cross) {
    var s = document.createElement("script"); s.async = true; s.src = src;
    if (cross) s.crossOrigin = "anonymous";
    document.head.appendChild(s);
  }
  function loadCmp(c) {
    if (state.cmp) return; state.cmp = true;
    // Mode consentement Google v2 : tout refusé par défaut, le bandeau de Google met à jour après le choix.
    root.dataLayer = root.dataLayer || [];
    root.gtag = root.gtag || function () { root.dataLayer.push(arguments); };
    root.gtag("consent", "default", { ad_storage: "denied", ad_user_data: "denied", ad_personalization: "denied", analytics_storage: "denied", wait_for_update: 500 });
    addScript("https://fundingchoicesmessages.google.com/i/" + c.publisherId.replace(/^ca-/, "") + "?ers=1");
    (function signal() {   // signal attendu par le bandeau de Google
      if (root.frames && root.frames.googlefcPresent) return;
      if (!document.body) { setTimeout(signal, 0); return; }
      var f = document.createElement("iframe"); f.name = "googlefcPresent"; f.style.display = "none"; f.setAttribute("aria-hidden", "true");
      document.body.appendChild(f);
    })();
    var started = Date.now();
    (function waitTcf() {
      if (typeof root.__tcfapi !== "function") {
        if (Date.now() - started < CMP_TIMEOUT) setTimeout(waitTcf, 250);   // bandeau bloqué ou absent : aucune annonce
        return;
      }
      root.__tcfapi("addEventListener", 2, function (tc, ok) {
        if (!ok) return;
        var d = tcfAllows(tc); if (d === null) return;
        state.consent = d;
        render();
      });
    })();
    var link = document.getElementById("pub-consent-wrap");   // lien « Gérer les cookies » du pied de page
    if (link) link.hidden = false;
  }
  function loadAdScript(c) {
    if (state.script) return; state.script = true;
    addScript("https://pagead2.googlesyndication.com/pagead/js/adsbygoogle.js?client=" + encodeURIComponent(c.publisherId), true);
  }
  function fill(slot, c, name) {
    if (slot.querySelector("ins.adsbygoogle")) return;
    var ins = document.createElement("ins");
    ins.className = "adsbygoogle";
    ins.style.display = "inline-block"; ins.style.width = "100%"; ins.style.height = "100px";   // format discret fixe, adapté au mobile
    ins.setAttribute("data-ad-client", c.publisherId);
    ins.setAttribute("data-ad-slot", c.slots[name]);
    if (c.underAgeOfConsent !== false) ins.setAttribute("data-tag-for-under-age-of-consent", "1");
    slot.textContent = "";
    var tag = document.createElement("span"); tag.className = "ad-tag"; tag.textContent = "PUBLICITÉ";
    slot.append(tag, ins);
    try { (root.adsbygoogle = root.adsbygoogle || []).push({}); } catch (e) { /* ignore */ }
  }
  function render(ads, premium) {
    if (ads !== undefined) { state.ads = ads; state.premium = !!premium; }
    var c = cfg(), d = decide(c, state.ads, { premium: state.premium });
    var slots = document.querySelectorAll(".ad-slot");
    if (!d.active) { slots.forEach(function (s) { s.hidden = true; }); return d; }
    loadCmp(c);
    var ingame = document.body.classList.contains("ingame");
    slots.forEach(function (s) {
      var name = s.getAttribute("data-slot"), view = s.closest("section");
      var ok = state.consent === true && !ingame && slotAllowed(c, state.ads, name) && view && view.id === PLACES[name];
      s.hidden = !ok;
      if (ok && !view.hidden) fill(s, c, name);   // rempli seulement quand l'écran est affiché (largeur connue)
    });
    if (state.consent === true) loadAdScript(c);
    return d;
  }
  function manage() {   // « Gérer mes cookies » : rouvre le choix du bandeau de Google
    root.googlefc = root.googlefc || {}; root.googlefc.callbackQueue = root.googlefc.callbackQueue || [];
    root.googlefc.callbackQueue.push({ CONSENT_DATA_READY: function () { root.googlefc.showRevocationMessage(); } });
  }
  root.addEventListener("hashchange", function () { if (state.ads) setTimeout(render, 0); });
  document.addEventListener("click", function (e) {
    var a = e.target && e.target.closest && e.target.closest("#pub-consent");
    if (a) { e.preventDefault(); manage(); }
  });

  api.render = render; api.manage = manage; api.state = state;
  root.BGAds = api;
})(typeof window !== "undefined" ? window : globalThis);

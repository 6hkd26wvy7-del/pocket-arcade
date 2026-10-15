// Capture d'une VRAIE partie de BoyBlocks (le vrai site, le vrai moteur), jouée par un robot, filmée en 1080x1920.
// Le site est servi localement depuis site/index.html, sans compte ni base de données : rien n'est envoyé nulle part.
import fs from "node:fs";
import { createRequire } from "node:module";
const require = createRequire(import.meta.url);
const { chromium } = require("playwright");
import * as BB from "../shared/boyblocks-engine.js";

const ROOT = new URL("../", import.meta.url).pathname;

// Robot : cherche le coup qui rapporte le plus (lignes, combos), puis celui qui garde le plus d'espace.
function meilleurCoup(g) {
  let best = null, bs = -1e9;
  for (let s = 0; s < 3; s++) {
    if (!g.pieces[s]) continue;
    const sh = BB.PIECES[g.pieces[s].p];
    for (let r = 0; r <= 8 - sh.h; r++) for (let c = 0; c <= 8 - sh.w; c++) {
      if (!BB.fits(g.grid, sh, r, c)) continue;
      const cp = JSON.parse(JSON.stringify(g)); const x = BB.place(cp, s, r, c);
      const sc = x.gain * 3 + cp.grid.filter((v) => !v).length + (x.over ? -500 : 0);
      if (sc > bs) { bs = sc; best = [s, r, c, sh]; }
    }
  }
  return best;
}

// Choisit une graine qui donne une belle partie (combos, lignes) en la simulant d'abord : la vidéo montre du vrai jeu.
export function choisirPartie(graineDepart, essais = 40, maxCoups = 60) {
  let meilleure = null;
  for (let i = 0; i < essais; i++) {
    const seed = (graineDepart + i * 7919) >>> 0, g = BB.newGame(seed, { ensureFit: true, rules: 2 });
    let combo = 0, lignes = 0;
    while (!g.over && g.moves < maxCoups) { const m = meilleurCoup(g); if (!m) break; const x = BB.place(g, m[0], m[1], m[2]); combo = Math.max(combo, x.streak); lignes += x.lines; }
    const note = lignes * 10 + combo * 25 + g.score / 20;
    if (!meilleure || note > meilleure.note) meilleure = { seed, note, score: g.score, combo, lignes, coups: g.moves };
  }
  return meilleure;
}

export async function capturer({ seed, dossier, maxCoups = 60 }) {
  const html = fs.readFileSync(ROOT + "site/index.html", "utf8");
  const fake = `window.supabase={createClient:function(){var ok=function(d){return Promise.resolve({data:d,error:null})};
    return {auth:{onAuthStateChange:function(f){f('INITIAL_SESSION',{user:{id:'demo',email:'demo@boygames'}})},getSession:function(){return ok({session:{access_token:'x'}})},signOut:function(){return ok({})}},
      from:function(){return {select:function(){return {eq:function(){return {maybeSingle:function(){return ok({pseudo:'BOYGAMES',country:'FR'})}}},order:function(){var r=ok([]);r.limit=function(){return ok([])};return r}}}}},
      rpc:function(n){ if(n==='boyblocks_start_v2') return ok({run_id:'demo',seed:${seed},rules:2});
        if(n==='boyblocks_finish') return ok({xp:0,bc:0,level:1,level_up:false,new_badges:[]});
        if(n==='me') return ok({pseudo:'BOYGAMES',avatar:'av_01',xp:0,level:1,level_start_xp:0,next_level_xp:50,bc:0,badges:[],items:[],streak:0,daily_claimed_today:true});
        if(n==='sync_tiers'||n==='my_missions'||n==='my_notifications') return ok([]);
        return ok(null); }};}};`;
  const b = await chromium.launch();
  // Écran de téléphone 360x640 à densité 3 : Chromium envoie des images natives en 1080x1920 (flux « screencast »).
  const ctx = await b.newContext({ viewport: { width: 360, height: 640 }, deviceScaleFactor: 3, hasTouch: true });
  const page = await ctx.newPage();
  await page.addInitScript(() => {
    window.__synced = 1;
    try { localStorage.setItem("bb-sound", "0"); } catch (e) { /* ignore */ }
    document.addEventListener("DOMContentLoaded", () => {
      const st = document.createElement("style");   // tournage : seulement le jeu à l'écran
      st.textContent = "#g-exit,#bug-fab,.stage .msg,.stage .row{visibility:hidden!important}";
      document.head.append(st);
    });
  });
  await page.route("**/*", (r) => {
    const u = r.request().url();
    if (u.startsWith("http://boygames.local/")) {
      if (u === "http://boygames.local/" || u.startsWith("http://boygames.local/?")) return r.fulfill({ contentType: "text/html", body: html });
      if (u.includes("config")) return r.fulfill({ contentType: "text/javascript", body: 'window.ARCADE_CONFIG={SUPABASE_URL:"https://demo.supabase.co",SUPABASE_ANON_KEY:"demo"};' });
      return r.fulfill({ status: 404, body: "" });
    }
    if (u.includes("supabase.js")) return r.fulfill({ contentType: "text/javascript", body: fake });
    return r.continue();                                                      // polices Google : rendu fidèle
  });
  // images du flux, horodatées : la vidéo est reconstruite avec les vraies durées entre deux images
  const imgDir = dossier + "/images"; fs.mkdirSync(imgDir, { recursive: true });
  const images = [];
  const cdp = await ctx.newCDPSession(page);
  cdp.on("Page.screencastFrame", async (f) => {
    const nom = imgDir + "/" + String(images.length).padStart(5, "0") + ".jpg";
    fs.writeFileSync(nom, Buffer.from(f.data, "base64"));
    images.push({ nom, t: f.metadata.timestamp });
    try { await cdp.send("Page.screencastFrameAck", { sessionId: f.sessionId }); } catch (e) { /* page fermée */ }
  });
  await cdp.send("Page.startScreencast", { format: "jpeg", quality: 88, maxWidth: 1080, maxHeight: 1920, everyNthFrame: 1 });
  const t0 = Date.now();
  // d'abord l'accueil (le compte de démonstration se connecte), puis le jeu : la partie démarre avec la bonne graine
  await page.goto("http://boygames.local/#menu"); await page.waitForTimeout(1200);
  await page.evaluate(() => { location.hash = "#boyblocks"; }); await page.waitForTimeout(1500);
  const debut = (Date.now() - t0) / 1000;
  const bx = await page.locator("#bb-screen").boundingBox(), kx = bx.width / 720, ky = bx.height / 1040;
  const P = (x, y) => [bx.x + x * kx, bx.y + y * ky];
  const g = BB.newGame(seed, { ensureFit: true, rules: 2 }), moments = [];
  while (!g.over && g.moves < maxCoups) {
    const m = meilleurCoup(g); if (!m) break;
    const [s, r, c, sh] = m, sw = (720 - 96) / 3;
    const [sx, sy] = P(48 + s * sw + sw / 2, 818 + (1040 - 818 - 20) / 2), [tx, ty] = P(48 + (c + sh.w / 2) * 78, 148 + (r + sh.h / 2) * 78 + 170);
    await page.mouse.move(sx, sy); await page.mouse.down();
    await page.mouse.move(tx, ty, { steps: 12 }); await page.waitForTimeout(120); await page.mouse.up();
    const x = BB.place(g, s, r, c);
    if (x.lines > 0) moments.push({ t: (Date.now() - t0) / 1000, lignes: x.lines, combo: x.streak, score: g.score });
    await page.waitForTimeout(x.lines > 0 ? 650 : 260);
  }
  await page.waitForTimeout(1800);
  const fin = (Date.now() - t0) / 1000;
  await cdp.send("Page.stopScreencast");
  await ctx.close(); await b.close();
  // liste « concat » pour ffmpeg : chaque image dure jusqu'à la suivante ; le temps 0 = début de la capture (t0)
  const origine = t0 / 1000, lignes = [];
  images.forEach((im, i) => {
    const suivante = i + 1 < images.length ? images[i + 1].t : origine + fin;
    lignes.push("file '" + im.nom + "'", "duration " + Math.max(0.001, suivante - im.t).toFixed(4));
  });
  if (images.length) lignes.push("file '" + images[images.length - 1].nom + "'");
  const video = dossier + "/images.txt";
  fs.writeFileSync(video, lignes.join("\n"));
  const decalage = images.length ? images[0].t - origine : 0;      // la vidéo commence à la 1re image
  return { video, concat: true, imgDir, debut: Math.max(0, debut - decalage), fin: fin - decalage, decalage,
           moments: moments.map((m) => ({ ...m, t: m.t - decalage })), score: g.score, combo: g.best_streak, lignes: g.lines, coups: g.moves };
}

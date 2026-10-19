// Mot de passe oublié (iPhone) : lien …/?reset=JETON -> connexion -> nouveau mot de passe ; lien expiré ;
// changement depuis le profil ; génération du lien par le Fondateur depuis la fiche joueur.
import { createRequire } from 'module'; const require=createRequire(import.meta.url); const { webkit, devices } = require('playwright');
import fs from 'fs';
const ROOT=new URL('../../', import.meta.url).pathname, FT=new URL('./', import.meta.url).pathname;
const html = fs.readFileSync(ROOT+'site/index.html','utf8');
const fail = (m) => { throw new Error(m); };
const b=await webkit.launch();
async function newPage(init) {
  const ctx=await b.newContext(devices['iPhone 13']); const page=await ctx.newPage();
  await page.addInitScript(()=>{ window.__synced=1; }); if (init) await page.addInitScript(init);
  const errs=[]; page.on('pageerror',e=>errs.push(String(e.stack).slice(0,300))); page.__errs=errs;
  page.on('dialog', d=>d.accept());
  await page.route('**/*', r=>{ const u=r.request().url();
    if(u.startsWith('http://x.test/')) { if(u==='http://x.test/'||u.startsWith('http://x.test/?')||u.startsWith('http://x.test/#')) return r.fulfill({contentType:'text/html',body:html});
      if(u.endsWith('config.js')) return r.fulfill({contentType:'text/javascript',body:'window.ARCADE_CONFIG={SUPABASE_URL:"https://x.supabase.co",SUPABASE_ANON_KEY:"k"};'});
      return r.fulfill({status:404,body:''}); }
    if(u.includes('supabase.js')) return r.fulfill({contentType:'text/javascript',body:fs.readFileSync(FT+'fake5.js','utf8')}); return r.fulfill({status:200,body:'',contentType:'text/css'}); });
  return page;
}
// 1. lien valide
let page = await newPage();
await page.goto('http://x.test/?reset=abcdefghijklmnopqrstuvwxyz0123'); await page.waitForTimeout(1000);
const otp = await page.evaluate(()=>window.__otp), url = page.url();
const open = await page.evaluate(()=>{ const d=[...document.querySelectorAll('#acc-body details')].find(x=>/MOT DE PASSE/.test(x.textContent)); return d && d.open; });
await page.fill('#in-newpass', 'nouveau123'); await page.fill('#in-newpass2', 'autre1234'); await page.tap('#acc-body >> text=ENREGISTRER'); await page.waitForTimeout(200);
const mismatch = await page.textContent('#acc-msg');
await page.fill('#in-newpass2', 'nouveau123'); await page.tap('#acc-body >> text=ENREGISTRER'); await page.waitForTimeout(300);
const done = await page.textContent('#acc-msg'), newPass = await page.evaluate(()=>window.__newPass);
console.log('lien | jeton vérifié :', otp && otp.type, '| adresse nettoyée :', !/reset=/.test(url), '| formulaire ouvert :', open, '|', mismatch, '|', done);
if (!otp || otp.token_hash !== 'abcdefghijklmnopqrstuvwxyz0123' || otp.type !== 'recovery' || /reset=/.test(url) || !open || !/identiques/.test(mismatch) || !/modifié/.test(done) || newPass !== 'nouveau123') fail('lien de réinitialisation');
if (page.__errs.length) fail(page.__errs.join('\n'));
// 2. lien expiré
page = await newPage(()=>{ window.__otpFail=1; });
await page.goto('http://x.test/?reset=abcdefghijklmnopqrstuvwxyz0123'); await page.waitForTimeout(1000);
const expired = await page.textContent('#acc-msg');
console.log('lien expiré :', expired);
if (!/expiré/.test(expired)) fail('lien expiré');
// 3. génération par le Fondateur depuis la fiche
page = await newPage(()=>{ window.__role='founder'; window.__players=[{pseudo:'Joh17',country:'FR',created_at:'2026-10-15T12:52:41Z',last_sign_in:null,confirmed:true,level:3,xp:200,bc:50,games:11,last_game:null,beta:true,role:null,banned:false,badges:[]}]; });
await page.goto('http://x.test/#joueurs'); await page.waitForTimeout(900);
await page.tap('#jo-body .jo-row >> nth=0'); await page.waitForTimeout(500);
await page.tap('text=LIEN MOT DE PASSE OUBLIÉ'); await page.waitForTimeout(400);
const inv = await page.evaluate(()=>window.__invoked), shown = await page.textContent('#jo-body');
console.log('fiche | fonction :', inv && inv.name, JSON.stringify(inv && inv.body), '| lien affiché :', /\?reset=HASHEDTOKEN/.test(shown), '| sans e-mail :', !/@/.test(shown));
if (!inv || inv.name !== 'admin-reset-link' || inv.body.pseudo !== 'Joh17' || !/\?reset=HASHEDTOKEN/.test(shown) || /@/.test(shown)) fail('lien depuis la fiche');
if (page.__errs.length) fail(page.__errs.join('\n'));
await b.close(); console.log('motdepasse OK');

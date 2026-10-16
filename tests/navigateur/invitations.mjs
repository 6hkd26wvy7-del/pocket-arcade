// Invitations bêta sur iPhone : lien …/?invite=CODE (admis à la connexion, code retiré de l'adresse), code tapé dans le
// profil, création / partage / liste des invitations par l'administration.
import { createRequire } from 'module'; const require=createRequire(import.meta.url); const { webkit, devices } = require('playwright');
import fs from 'fs';
const ROOT=new URL('../../', import.meta.url).pathname, FT=new URL('./', import.meta.url).pathname; fs.mkdirSync(FT+'captures',{recursive:true});
const html = fs.readFileSync(ROOT+'site/index.html','utf8');
const fail = (m) => { throw new Error(m); };
const b=await webkit.launch();
async function newPage(init) {
  const ctx=await b.newContext(devices['iPhone 13']); const page=await ctx.newPage();
  await page.addInitScript(init || (()=>{})); await page.addInitScript(()=>{ window.__synced=1; });
  const errs=[]; page.on('pageerror',e=>errs.push(String(e.stack).slice(0,300))); page.__errs=errs;
  await page.route('**/*', r=>{ const u=r.request().url();
    if(u.startsWith('http://x.test/')) { if(u==='http://x.test/'||u.startsWith('http://x.test/?')||u.startsWith('http://x.test/#')) return r.fulfill({contentType:'text/html',body:html});
      if(u.endsWith('config.js')) return r.fulfill({contentType:'text/javascript',body:'window.ARCADE_CONFIG={SUPABASE_URL:"https://x.supabase.co",SUPABASE_ANON_KEY:"k"};'});
      return r.fulfill({status:404,body:''}); }
    if(u.includes('supabase.js')) return r.fulfill({contentType:'text/javascript',body:fs.readFileSync(FT+'fake5.js','utf8')}); return r.fulfill({status:200,body:'',contentType:'text/css'}); });
  return page;
}
// 1. lien d'invitation
let page = await newPage(()=>{ window.__access={beta_on:true,allowed:false}; });
await page.goto('http://x.test/?invite=ab12cd34#menu'); await page.waitForTimeout(900);
const redeemed = await page.evaluate(()=>window.__redeemed||[]), url = page.url(), greet = await page.textContent('#menu-status');
const stored = await page.evaluate(()=>localStorage.getItem('boygames-invite'));
console.log('lien | code utilisé :', redeemed.join(','), '| adresse nettoyée :', !/invite/.test(url), '| message :', greet, '| code effacé :', stored === null);
if (redeemed[0] !== 'AB12CD34' || /invite/.test(url) || !/bienvenue dans la bêta/i.test(greet) || stored !== null) fail('lien d\'invitation');
if (page.__errs.length) fail(page.__errs.join('\n'));
// 2. code tapé dans le profil (mauvais puis bon)
page = await newPage(()=>{ window.__access={beta_on:true,allowed:false}; });
await page.goto('http://x.test/#compte'); await page.waitForTimeout(900);
const box = await page.isVisible('#in-invite');
await page.fill('#in-invite', 'ZZZZ9999'); await page.tap('text=VALIDER'); await page.waitForTimeout(300);
const bad = await page.textContent('#acc-msg');
await page.fill('#in-invite', 'ab12-cd34'); await page.tap('text=VALIDER'); await page.waitForTimeout(500);
const good = await page.textContent('#acc-msg'), boxAfter = await page.isVisible('#in-invite');
await page.screenshot({path:FT+'captures/invitation-profil-iphone.png'});
console.log('profil | champ visible :', box, '| mauvais code :', bad, '| bon code :', good, '| champ masqué ensuite :', !boxAfter);
if (!box || !/inconnu/.test(bad) || !/bienvenue/i.test(good) || boxAfter) fail('code dans le profil');
// 3. administration
page = await newPage(()=>{ window.__role='founder'; window.__access={beta_on:true,allowed:true}; });
await page.goto('http://x.test/#admin'); await page.waitForTimeout(1200);
await page.tap('text=CRÉER UNE INVITATION'); await page.waitForTimeout(400);
const created = await page.textContent('#adm-body'), args = await page.evaluate(()=>window.__calls.filter(c=>c.startsWith('staff_beta_invite_create')).pop());
await page.screenshot({path:FT+'captures/invitation-admin-iphone.png'});
console.log('admin | code affiché :', /K7P2Q9XZ/.test(created), '| lien :', /\?invite=K7P2Q9XZ/.test(created), '| paramètres :', args, '| listée :', (created.match(/K7P2Q9XZ — 0\/1/)||[]).length);
if (!/\?invite=K7P2Q9XZ/.test(created) || !/"p_max_uses":1,"p_days":14/.test(args) || !/K7P2Q9XZ — 0\/1/.test(created)) fail('admin invitations');
if (page.__errs.length) fail(page.__errs.join('\n'));
await b.close(); console.log('invitations OK');

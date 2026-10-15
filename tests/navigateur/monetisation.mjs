// Monétisation (préparation) : emplacement de pub, continuation par vidéo (Snake), carte Premium, aucun pub pour un Premium.
import { createRequire } from 'module'; const require=createRequire(import.meta.url); const { webkit, devices } = require('playwright');
const ROOT=new URL('../../', import.meta.url).pathname, FT=new URL('./', import.meta.url).pathname;
import fs from 'fs'; fs.mkdirSync(FT+'captures',{recursive:true});
const html = fs.readFileSync(ROOT+'test/index.html','utf8');
const b=await webkit.launch();
async function open(premium){
  const ctx=await b.newContext({...devices['iPhone 13']}); const page=await ctx.newPage();
  await page.addInitScript((p)=>{ window.__synced=1; window.__premium=p; }, premium);
  const errs=[]; page.on('pageerror',e=>errs.push(String(e).slice(0,200)));
  await page.route('**/*', r=>{ const u=r.request().url();
   if(u.startsWith('http://x.test/')) { if(u==='http://x.test/'||u.startsWith('http://x.test/?')) return r.fulfill({contentType:'text/html',body:html}); if(u.includes('config')) return r.fulfill({contentType:'text/javascript',body:'window.ARCADE_CONFIG={SUPABASE_URL:"https://x.supabase.co",SUPABASE_ANON_KEY:"k"};'}); return r.fulfill({status:404,body:''}); }
   if(u.includes('supabase.js')) return r.fulfill({contentType:'text/javascript',body:fs.readFileSync(FT+'fake5.js','utf8')}); return r.fulfill({status:200,body:'',contentType:'text/css'}); });
  return { page, errs, ctx };
}
// 1. joueur normal
let { page, errs } = await open(false);
await page.goto('http://x.test/#menu'); await page.waitForTimeout(800);
console.log('pub accueil visible :', await page.isVisible('.ad-slot[data-slot="home"]'));
await page.goto('http://x.test/#snake'); await page.waitForTimeout(500);
const c = await page.locator('#screen').boundingBox();
await page.mouse.move(c.x+c.width/2, c.y+c.height/2); await page.mouse.down(); await page.mouse.move(c.x+c.width/2+60, c.y+c.height/2, {steps:4}); await page.mouse.up();
await page.waitForSelector('.btn-continue', { timeout: 15000 });
const ranked1 = await page.evaluate(()=>(window.__ranked||[]).length);
console.log('bouton continuer après défaite : true | parties classées envoyées (score 0 = aucune) :', ranked1);
await page.click('.btn-continue'); await page.waitForTimeout(600);
console.log('vidéo de test affichée :', await page.isVisible('#ad-modal'));
await page.screenshot({path:FT+'captures/video-test.png'});
await page.waitForSelector('#ad-modal', { state: 'hidden', timeout: 9000 });
console.log('reprise :', await page.innerText('#snake-msg'));
await page.mouse.move(c.x+c.width/2, c.y+c.height/2); await page.mouse.down(); await page.mouse.move(c.x+c.width/2, c.y+c.height/2-60, {steps:4}); await page.mouse.up();
await page.waitForFunction(()=>window.__cont, null, { timeout: 15000 });
console.log('score final continué :', JSON.stringify(await page.evaluate(()=>window.__cont)), '| classé envoyé de nouveau :', (await page.evaluate(()=>(window.__ranked||[]).length)) !== ranked1);
console.log('plus de 2e continuation :', !(await page.isVisible('.btn-continue')));
await page.goto('http://x.test/#compte'); await page.waitForTimeout(800);
console.log('carte Premium :', /BOYGAMES PREMIUM/.test(await page.innerText('#acc-body')) && /0,99 €/.test(await page.innerText('#acc-body')));
console.log('errors', JSON.stringify(errs));
// 2. joueur Premium : aucune pub, badge
({ page, errs } = await open(true));
await page.goto('http://x.test/#menu'); await page.waitForTimeout(800);
console.log('premium : pub cachée :', !(await page.isVisible('.ad-slot[data-slot="home"]')), '| badge :', await page.isVisible('#me-card .prem'));
console.log('errors', JSON.stringify(errs));
await b.close();

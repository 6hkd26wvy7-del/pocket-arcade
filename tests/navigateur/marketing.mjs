// Onglet Marketing (administration) : file de validation, aperçu privé, validation avec date et textes corrigés.
import { createRequire } from 'module'; const require=createRequire(import.meta.url); const { chromium } = require('playwright');
const ROOT=new URL('../../', import.meta.url).pathname, FT=new URL('./', import.meta.url).pathname;
import fs from 'fs'; fs.mkdirSync(FT+'captures',{recursive:true});
const html = fs.readFileSync(ROOT+'site/index.html','utf8');
const b=await chromium.launch(); const page=await (await b.newContext({viewport:{width:390,height:800},hasTouch:true})).newPage();
const errs=[]; page.on('pageerror',e=>errs.push(String(e))); page.on('dialog',d=>d.accept());
await page.route('**/*', r=>{ const u=r.request().url();
 if(u.startsWith('http://x.test/')) { if(u==='http://x.test/'||u.startsWith('http://x.test/?')) return r.fulfill({contentType:'text/html',body:html}); if(u.endsWith('config.js')) return r.fulfill({contentType:'text/javascript',body:'window.ARCADE_CONFIG={SUPABASE_URL:"https://x.supabase.co",SUPABASE_ANON_KEY:"k"};'}); return r.fulfill({status:404,body:''}); }
 if(u.includes('supabase.js')) return r.fulfill({contentType:'text/javascript',body:fs.readFileSync(FT+'fake4.js','utf8')}); return r.fulfill({status:200,body:'',contentType:'text/css'}); });
await page.goto('http://x.test/#admin'); await page.waitForTimeout(1000);
console.log('lien marketing :', await page.isVisible('a:has-text("OUVRIR LE MARKETING")'));
await page.click('a:has-text("OUVRIR LE MARKETING")'); await page.waitForTimeout(800);
console.log('vidéo listée :', await page.isVisible('.mk-card video'), '| aperçu privé demandé :', JSON.stringify(await page.evaluate(()=>window.__signed)));
await page.fill('.mk-card label:has-text("Accroche") + input', 'Combo x6 en direct');
await page.click('.mk-card button:has-text("VALIDER")'); await page.waitForTimeout(400);
const mk = await page.evaluate(()=>window.__mk);
console.log('validation envoyée :', mk.p_decision, '| accroche :', mk.p_accroche, '| date ISO :', /^\d{4}-\d\d-\d\dT/.test(mk.p_scheduled_for), '| hashtags :', JSON.stringify(mk.p_hashtags));
console.log('onglet actif :', await page.$eval('.nav a.on span', e=>e.textContent));
await page.screenshot({path:FT+'captures/marketing.png',fullPage:true});
console.log('errors', JSON.stringify(errs)); await b.close();

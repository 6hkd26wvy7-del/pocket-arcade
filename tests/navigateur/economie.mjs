// Panneau « Économie BOYCOINS » de l'administration (faux Supabase, compte fondateur).
import { createRequire } from 'module'; const require=createRequire(import.meta.url); const { chromium } = require('playwright');
const ROOT=new URL('../../', import.meta.url).pathname, FT=new URL('./', import.meta.url).pathname;
import fs from 'fs'; fs.mkdirSync(FT+'captures',{recursive:true});
const html = fs.readFileSync(ROOT+'site/index.html','utf8');
const b=await chromium.launch(); const page=await (await b.newContext({viewport:{width:390,height:800},hasTouch:true})).newPage();
const errs=[]; page.on('pageerror',e=>errs.push(String(e))); page.on('dialog',d=>d.accept());
await page.route('**/*', r=>{ const u=r.request().url();
 if(u.startsWith('http://x.test/')) { if(u==='http://x.test/'||u.startsWith('http://x.test/?')) return r.fulfill({contentType:'text/html',body:html}); if(u.endsWith('config.js')) return r.fulfill({contentType:'text/javascript',body:'window.ARCADE_CONFIG={SUPABASE_URL:"https://x.supabase.co",SUPABASE_ANON_KEY:"k"};'}); return r.fulfill({status:404,body:''}); }
 if(u.includes('supabase.js')) return r.fulfill({contentType:'text/javascript',body:fs.readFileSync(FT+'fake4.js','utf8')}); return r.fulfill({status:200,body:'',contentType:'text/css'}); });
await page.goto('http://x.test/#admin'); await page.waitForTimeout(1200);
console.log('panneau économie :', await page.isVisible('text=ÉCONOMIE BOYCOINS'));
const cap = page.locator('label:has-text("Plafond de BC") + input'); await cap.fill('40');
await page.click('button:has-text("ENREGISTRER LE PLAFOND")'); await page.waitForTimeout(400);
await page.click('button:has-text("ENREGISTRER LE BONUS DE CONNEXION")'); await page.waitForTimeout(400);
console.log('envoyé :', JSON.stringify(await page.evaluate(()=>window.__eco)));
await page.screenshot({path:FT+'captures/admin-economie.png',fullPage:true});
await page.goto('http://x.test/#menu'); await page.waitForTimeout(800);
console.log('bonus affiché :', (await page.$$eval('.daily b', e=>e.map(x=>x.textContent))).join(','));
console.log('errors', JSON.stringify(errs)); await b.close();

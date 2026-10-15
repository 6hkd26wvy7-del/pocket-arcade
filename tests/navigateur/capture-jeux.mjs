// Captures d'écran des jeux sur iPhone (WebKit) avec le faux Supabase, pour vérifier l'affichage.
import { createRequire } from 'module'; const require=createRequire(import.meta.url); const { webkit, devices } = require('playwright');
const ROOT=new URL('../../', import.meta.url).pathname, FT=new URL('./', import.meta.url).pathname;
import fs from 'fs'; fs.mkdirSync(FT+'captures',{recursive:true});
const html = fs.readFileSync(ROOT+'test/index.html','utf8');
const b=await webkit.launch(); const ctx=await b.newContext({...devices['iPhone 13']}); const page=await ctx.newPage();
await page.addInitScript(()=>{ window.__synced=1; });
const errs=[]; page.on('pageerror',e=>errs.push(String(e).slice(0,300)));
await page.route('**/*', r=>{ const u=r.request().url();
 if(u.startsWith('http://x.test/')) { if(u==='http://x.test/'||u.startsWith('http://x.test/?')) return r.fulfill({contentType:'text/html',body:html}); if(u.endsWith('.js')&&u.includes('config')) return r.fulfill({contentType:'text/javascript',body:'window.ARCADE_CONFIG={SUPABASE_URL:"https://x.supabase.co",SUPABASE_ANON_KEY:"k"};'}); return r.fulfill({status:404,body:''}); }
 if(u.includes('supabase.js')) return r.fulfill({contentType:'text/javascript',body:fs.readFileSync(FT+'fake5.js','utf8')}); return r.fulfill({status:200,body:'',contentType:'text/css'}); });
const games = (process.argv[2] || 'snake,space,boyblocks,menu').split(',');
for (const h of games) {
  await page.goto('http://x.test/#'+h); await page.waitForTimeout(600);
  if (h !== 'menu') { const c = await page.locator('section:not([hidden]) canvas').first().boundingBox(); if (c) { await page.mouse.click(c.x+c.width/2, c.y+c.height/2); await page.waitForTimeout(h==='space'?2500:1200); } }
  await page.screenshot({path:FT+'captures/jeu-'+h+'.png'});
  console.log('capture', h);
}
console.log('errors', JSON.stringify(errs)); await b.close();

import { createRequire } from 'module'; const require=createRequire('/opt/npm-tools/node_modules/'); const { chromium } = require('playwright');
import fs from 'fs'; const html = fs.readFileSync('/home/claude/pocket-arcade/site/index.html','utf8');
const b=await chromium.launch(); const page=await (await b.newContext({viewport:{width:390,height:800},hasTouch:true})).newPage();
const errs=[]; page.on('pageerror',e=>errs.push(String(e.stack).slice(0,300)));
await page.route('**/*', r=>{ const u=r.request().url();
 if(u.startsWith('http://x.test/')) { if(u==='http://x.test/'||u.startsWith('http://x.test/?')) return r.fulfill({contentType:'text/html',body:html}); if(u.endsWith('config.js')) return r.fulfill({contentType:'text/javascript',body:'window.ARCADE_CONFIG={SUPABASE_URL:"https://x.supabase.co",SUPABASE_ANON_KEY:"k"};'}); return r.fulfill({status:404,body:''}); }
 if(u.includes('supabase.js')) return r.fulfill({contentType:'text/javascript',body:fs.readFileSync('/tmp/ft/fake5.js','utf8')}); return r.fulfill({status:200,body:'',contentType:'text/css'}); });
for (const h of ['snake','blocks','space','boyblocks','arena','scores','menu']) { await page.goto('http://x.test/#'+h); await page.waitForTimeout(500); await page.keyboard.press('Enter'); await page.waitForTimeout(300);
  console.log(h, await page.evaluate(()=>document.body.classList.contains('ingame'))); }
console.log('errors',JSON.stringify(errs)); await b.close();

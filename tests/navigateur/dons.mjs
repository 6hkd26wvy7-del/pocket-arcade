// Dons volontaires (iPhone) : aucune carte tant que les dons sont désactivés ; carte « Soutenir » + lien externe une fois activés.
import { createRequire } from 'module'; const require=createRequire(import.meta.url); const { webkit, devices } = require('playwright');
import fs from 'fs';
const ROOT=new URL('../../', import.meta.url).pathname, FT=new URL('./', import.meta.url).pathname; fs.mkdirSync(FT+'captures',{recursive:true});
const html = fs.readFileSync(ROOT+'site/index.html','utf8');
const fail = (m) => { throw new Error(m); };
const b=await webkit.launch();
async function profil(init) {
  const page=await (await b.newContext(devices['iPhone 13'])).newPage();
  await page.addInitScript(()=>{ window.__synced=1; }); if (init) await page.addInitScript(init);
  await page.route('**/*', r=>{ const u=r.request().url();
    if(u.startsWith('http://x.test/')) { if(u==='http://x.test/'||u.startsWith('http://x.test/?')||u.startsWith('http://x.test/#')) return r.fulfill({contentType:'text/html',body:html});
      if(u.endsWith('config.js')) return r.fulfill({contentType:'text/javascript',body:'window.ARCADE_CONFIG={SUPABASE_URL:"https://x.supabase.co",SUPABASE_ANON_KEY:"k"};'});
      return r.fulfill({status:404,body:''}); }
    if(u.includes('supabase.js')) return r.fulfill({contentType:'text/javascript',body:fs.readFileSync(FT+'fake5.js','utf8')}); return r.fulfill({status:200,body:'',contentType:'text/css'}); });
  await page.goto('http://x.test/#compte'); await page.waitForTimeout(900);
  return page;
}
let page = await profil();
const off = await page.isVisible('text=SOUTENIR BOYGAMES');
page = await profil(()=>{ window.__donate={enabled:true,url:'https://ko-fi.com/boygames',message:''}; });
const on = await page.isVisible('text=SOUTENIR BOYGAMES');
const link = await page.getAttribute('text=FAIRE UN DON', 'href'), target = await page.getAttribute('text=FAIRE UN DON', 'target');
await page.locator('text=SOUTENIR BOYGAMES').scrollIntoViewIfNeeded(); await page.screenshot({path:FT+'captures/dons-iphone.png'});
console.log('désactivés : carte', off, '| activés : carte', on, link, target);
if (off || !on || link !== 'https://ko-fi.com/boygames' || target !== '_blank') fail('dons');
await b.close(); console.log('dons OK');

// Défi à distance (prototype v24) : après une partie classée, le site déclare la PARTIE (ticket), jamais un score ;
// la base relit elle-même le score de cette partie (invite_report_score(p_id, p_run)).
import { createRequire } from 'module'; const require=createRequire(import.meta.url); const { chromium } = require('playwright');
import fs from 'fs';
const ROOT=new URL('../../', import.meta.url).pathname, FT=new URL('./', import.meta.url).pathname;
const html = fs.readFileSync(ROOT+'site/index.html','utf8');
const fail = (m) => { throw new Error(m); };
const b=await chromium.launch(); const page=await (await b.newContext({viewport:{width:390,height:800}})).newPage();
await page.addInitScript(()=>{ window.__synced=1; Math.random = () => 99.5 / 429; });
const errs=[]; page.on('pageerror',e=>errs.push(String(e.stack).slice(0,300)));
await page.route('**/*', r=>{ const u=r.request().url();
  if(u.startsWith('http://x.test/')) { if(u==='http://x.test/'||u.startsWith('http://x.test/?')||u.startsWith('http://x.test/#')) return r.fulfill({contentType:'text/html',body:html});
    if(u.endsWith('config.js')) return r.fulfill({contentType:'text/javascript',body:'window.ARCADE_CONFIG={SUPABASE_URL:"https://x.supabase.co",SUPABASE_ANON_KEY:"k",ARENA_URL:"wss://arena.test"};'});
    return r.fulfill({status:404,body:''}); }
  if(u.includes('supabase.js')) return r.fulfill({contentType:'text/javascript',body:fs.readFileSync(FT+'fake5.js','utf8')}); return r.fulfill({status:200,body:'',contentType:'text/css'}); });
await page.goto('http://x.test/#amis'); await page.waitForTimeout(900);
await page.click('text=INVITER'); await page.waitForTimeout(200);
await page.click('text=À DISTANCE'); await page.waitForTimeout(200);
await page.click('text=SNAKE · 48 H'); await page.waitForTimeout(400);
const inv = await page.evaluate(()=>window.__inv);
await page.goto('http://x.test/#snake'); await page.waitForTimeout(800);
await page.keyboard.press('ArrowUp'); await page.waitForTimeout(150);
for (let i = 0; i < 40 && !(await page.evaluate(()=>window.__reported && window.__reported.length)); i++) await page.waitForTimeout(250);
const ranked = await page.evaluate(()=>window.__ranked||[]), reported = await page.evaluate(()=>window.__reported||[]);
console.log('défi envoyé :', JSON.stringify(inv), '| partie :', JSON.stringify(ranked), '| déclaration :', JSON.stringify(reported));
if (!inv || inv.p_mode !== 'async' || inv.p_game !== 'snake') fail('envoi du défi');
if (reported.length !== 1 || reported[0].p_id !== 'inv-1' || reported[0].p_run !== ranked[0].p_run || 'p_score' in reported[0]) fail('déclaration de la partie');
if (errs.length) fail(errs.join('\n'));
await b.close(); console.log('defis OK');

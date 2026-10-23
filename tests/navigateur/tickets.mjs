// Ticket de partie (v22) : une vraie partie de Snake demande un ticket au premier instant de jeu, puis envoie le score
// avec ce ticket (submit_score_v2) ; plus aucun appel à l'ancien submit_score.
import { createRequire } from 'module'; const require=createRequire(import.meta.url); const { chromium } = require('playwright');
import fs from 'fs';
const ROOT=new URL('../../', import.meta.url).pathname, FT=new URL('./', import.meta.url).pathname;
const html = fs.readFileSync(ROOT+'site/index.html','utf8');
const fail = (m) => { throw new Error(m); };
const b=await chromium.launch(); const page=await (await b.newContext({viewport:{width:390,height:800}})).newPage();
await page.addInitScript(()=>{ window.__synced=1; Math.random = () => 99.5 / 429; });   // première pomme en (9,5), droit devant le serpent qui monte
const errs=[]; page.on('pageerror',e=>errs.push(String(e.stack).slice(0,300)));
await page.route('**/*', r=>{ const u=r.request().url();
  if(u.startsWith('http://x.test/')) { if(u==='http://x.test/'||u.startsWith('http://x.test/?')||u.startsWith('http://x.test/#')) return r.fulfill({contentType:'text/html',body:html});
    if(u.endsWith('config.js')) return r.fulfill({contentType:'text/javascript',body:'window.ARCADE_CONFIG={SUPABASE_URL:"https://x.supabase.co",SUPABASE_ANON_KEY:"k"};'});
    return r.fulfill({status:404,body:''}); }
  if(u.includes('supabase.js')) return r.fulfill({contentType:'text/javascript',body:fs.readFileSync(FT+'fake5.js','utf8')}); return r.fulfill({status:200,body:'',contentType:'text/css'}); });
await page.goto('http://x.test/#snake'); await page.waitForTimeout(800);
await page.keyboard.press('ArrowUp'); await page.waitForTimeout(150);
const runs0 = await page.evaluate(()=>window.__runs||0);
for (let i = 0; i < 40 && !(await page.evaluate(()=>window.__ranked && window.__ranked.length)); i++) await page.waitForTimeout(250);
const ranked = await page.evaluate(()=>window.__ranked||[]), calls = await page.evaluate(()=>window.__calls.filter(c=>/^(submit_score|game_start)/.test(c)));
console.log('ticket demandé au départ :', runs0, '| envoi :', JSON.stringify(ranked), '| appels :', calls.join(' '));
if (runs0 !== 1 || !ranked.length || ranked[0].p_game !== 'snake' || ranked[0].p_run !== 'run-1' || calls.some(c=>/^submit_score\{/.test(c))) fail('ticket de partie');
await page.waitForTimeout(300);
const msg = await page.evaluate(()=>document.getElementById('snake-msg').textContent);
console.log('message :', msg);
if (!new RegExp('Score enregistré : '+ranked[0].p_score+' \\(record en ligne : '+ranked[0].p_score+'\\)').test(msg)) fail('« Score enregistré » doit citer le score confirmé par le serveur');
if (errs.length) fail(errs.join('\n'));
await b.close(); console.log('tickets OK');

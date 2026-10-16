// Pause contre BOYBOT sur iPhone : bouton PAUSE -> calque « PAUSE » -> REPRENDRE -> compte à rebours 3 s -> reprise.
// Pause automatique quand l'appli passe en arrière-plan. Aucun bouton Pause entre deux humains.
import { createRequire } from 'module'; const require=createRequire(import.meta.url); const { webkit, devices } = require('playwright');
import fs from 'fs';
const ROOT=new URL('../../', import.meta.url).pathname, FT=new URL('./', import.meta.url).pathname; fs.mkdirSync(FT+'captures',{recursive:true});
const html = fs.readFileSync(ROOT+'site/index.html','utf8');
const fail = (m) => { throw new Error(m); };
const b=await webkit.launch(); const ctx=await b.newContext(devices['iPhone 13']); const page=await ctx.newPage();
await page.addInitScript(()=>{ window.__synced=1;
  window.WebSocket = class { constructor(url){ this.url=url; this.readyState=0; this.l={}; window.__ws=this; setTimeout(()=>{this.readyState=1;(this.l.open||[]).forEach(f=>f({}));},150); }
    addEventListener(e,f){ (this.l[e]=this.l[e]||[]).push(f); } close(){ this.readyState=3; }
    emit(o){ (this.l.message||[]).forEach(f=>f({data:JSON.stringify(o)})); }
    send(d){ const m=JSON.parse(d); (window.__sent=window.__sent||[]).push(m); const ws=this;
      if(m.t==='hello'){ const bot=!!m.bot, names=['Quentin', bot?'BOYBOT 🤖':'Zoe'], bots=[false,bot];
        ws.emit({t:'lobby',code:'SABCD',kind:'snake',you:0,players:names,bots,phase:'countdown'}); ws.emit({t:'countdown',ms:30,players:names,bots});
        let tick=0; const body=(x,y,dx)=>[0,1,2].map(k=>({x:x-k*dx,y}));
        window.__emitState=()=>ws.emit({t:'state',kind:'snake',tick:++tick,over:false,players:[{body:body(3+tick%10,12,1),alive:true,score:0},{body:body(20-tick%10,12,-1),alive:true,score:0}],food:[{x:5,y:5}]});
        setTimeout(()=>window.__emitState(),60); } } }; });
const errs=[]; page.on('pageerror',e=>errs.push(String(e.stack).slice(0,300)));
await page.route('**/*', r=>{ const u=r.request().url();
  if(u.startsWith('http://x.test/')) { if(u==='http://x.test/'||u.startsWith('http://x.test/?')) return r.fulfill({contentType:'text/html',body:html});
    if(u.endsWith('config.js')) return r.fulfill({contentType:'text/javascript',body:'window.ARCADE_CONFIG={SUPABASE_URL:"https://x.supabase.co",SUPABASE_ANON_KEY:"k",ARENA_URL:"wss://arena.test"};'});
    return r.fulfill({status:404,body:''}); }
  if(u.includes('supabase.js')) return r.fulfill({contentType:'text/javascript',body:fs.readFileSync(FT+'fake5.js','utf8')}); return r.fulfill({status:200,body:'',contentType:'text/css'}); });
// --- partie entre humains : pas de bouton Pause
await page.goto('http://x.test/?h#arena'); await page.waitForTimeout(600);
await page.tap('#ar-create-S'); await page.waitForTimeout(500);
const humanBtn = await page.isVisible('#ar-pause'); if (humanBtn) fail('bouton Pause visible entre humains');
// --- contre BOYBOT
await page.goto('http://x.test/?b#arena'); await page.waitForTimeout(600);
await page.tap('#ar-bot-S'); await page.waitForTimeout(500);
if (!(await page.isVisible('#ar-pause'))) fail('bouton Pause absent contre BOYBOT');
await page.tap('#ar-pause'); await page.waitForTimeout(100);
if (!(await page.evaluate(()=>window.__sent.some(m=>m.t==='pause')))) fail('pause non envoyée');
await page.evaluate(()=>window.__ws.emit({t:'paused'})); await page.waitForTimeout(150);
const label1 = await page.textContent('#ar-pause'), msg1 = await page.textContent('#ar-msg');
await page.screenshot({path:FT+'captures/boybot-pause-iphone.png'});
// pendant la pause, glisser ne doit rien envoyer
const before = await page.evaluate(()=>window.__sent.length);
const box = await page.locator('#ar-screen').boundingBox();
await page.touchscreen.tap(box.x+box.width/2, box.y+box.height/2);
await page.mouse.move(box.x+50, box.y+100); 
await page.tap('#ar-pause'); await page.waitForTimeout(100);
const sentResume = await page.evaluate((n)=>window.__sent.slice(n).map(m=>m.t), before);
await page.evaluate(()=>window.__ws.emit({t:'resume',ms:3000})); await page.waitForTimeout(250);
const msg2 = await page.textContent('#ar-msg'), disabled = await page.isDisabled('#ar-pause');
await page.screenshot({path:FT+'captures/boybot-reprise-iphone.png'});
await page.waitForTimeout(1100); const msg3 = await page.textContent('#ar-msg');
await page.evaluate(()=>window.__emitState()); await page.waitForTimeout(150);
const label2 = await page.textContent('#ar-pause');
// arrière-plan -> pause automatique
await page.evaluate(()=>{ window.__sent.length=0; Object.defineProperty(document,'hidden',{configurable:true,get:()=>true}); document.dispatchEvent(new Event('visibilitychange')); });
const auto = await page.evaluate(()=>window.__sent.some(m=>m.t==='pause'));
console.log('humains : bouton', humanBtn, '| pause :', label1, '/', msg1, '| envoyé :', sentResume.join(','), '|', msg2, '→', msg3, '| bouton bloqué pendant le décompte :', disabled, '| après reprise :', label2, '| pause auto arrière-plan :', auto);
if (label1 !== 'REPRENDRE' || !/PAUSE/.test(msg1)) fail('affichage de pause');
if (sentResume.join(',') !== 'resume') fail('pendant la pause, seul « resume » doit partir : ' + sentResume);
if (!/Reprise dans 3/.test(msg2) || !/Reprise dans 2/.test(msg3) || !disabled) fail('compte à rebours');
if (label2 !== 'PAUSE') fail('bouton après reprise'); if (!auto) fail('pause automatique absente');
if (errs.length) fail(errs.join('\n'));
await b.close(); console.log('boybot-pause OK');

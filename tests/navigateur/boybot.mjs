// BOYBOT côté téléphone : section visible, choix de la difficulté, demande envoyée au serveur, robot clairement signalé.
import { createRequire } from 'module'; const require=createRequire(import.meta.url); const { chromium, webkit, devices } = require('playwright');
import fs from 'fs';
const ROOT=new URL('../../', import.meta.url).pathname, FT=new URL('./', import.meta.url).pathname; fs.mkdirSync(FT+'captures',{recursive:true});
const html = fs.readFileSync(ROOT+'site/index.html','utf8');
for (const [name, engine, opts] of [['chromium', chromium, {viewport:{width:390,height:800},hasTouch:true}], ['webkit-iphone', webkit, devices['iPhone 13']]]) {
  const b=await engine.launch(); const ctx=await b.newContext(opts); const page=await ctx.newPage();
  await page.addInitScript(()=>{ window.__synced=1;
    window.WebSocket = class { constructor(url){ this.url=url; this.readyState=0; this.l={}; window.__ws=this; setTimeout(()=>{this.readyState=1;(this.l.open||[]).forEach(f=>f({}));},200); }
      addEventListener(e,f){ (this.l[e]=this.l[e]||[]).push(f); } close(){ this.readyState=3; }
      emit(o){ (this.l.message||[]).forEach(f=>f({data:JSON.stringify(o)})); }
      send(d){ const m=JSON.parse(d); (window.__sent=window.__sent||[]).push(m);
        if(m.t==='hello'){ const code=this.url.split('/').pop(); const kind={S:'snake',P:'space',X:'boyblocks',Y:'boyblocks'}[code[0]];
          this.emit({t:'lobby',code,kind,you:0,players:['Quentin','BOYBOT 🤖'],bots:[false,true],phase:'countdown'}); this.emit({t:'countdown',ms:50,players:['Quentin','BOYBOT 🤖'],bots:[false,true]}); } } }; });
  const errs=[]; page.on('pageerror',e=>errs.push(String(e.stack).slice(0,300)));
  await page.route('**/*', r=>{ const u=r.request().url();
    if(u.startsWith('http://x.test/')) { if(u==='http://x.test/'||u.startsWith('http://x.test/?')) return r.fulfill({contentType:'text/html',body:html});
      if(u.endsWith('config.js')) return r.fulfill({contentType:'text/javascript',body:'window.ARCADE_CONFIG={SUPABASE_URL:"https://x.supabase.co",SUPABASE_ANON_KEY:"k",ARENA_URL:"wss://arena.test"};'});
      return r.fulfill({status:404,body:''}); }
    if(u.includes('supabase.js')) return r.fulfill({contentType:'text/javascript',body:fs.readFileSync(FT+'fake5.js','utf8')}); return r.fulfill({status:200,body:'',contentType:'text/css'}); });
  await page.goto('http://x.test/#arena'); await page.waitForTimeout(700);
  await page.locator('#ar-bot').scrollIntoViewIfNeeded(); await page.screenshot({path:FT+'captures/boybot-'+name+'.png'});
  const visible = await page.isVisible('#ar-bot-S');
  await page.tap('[data-bot-level="hard"]'); const pressed = await page.getAttribute('[data-bot-level="hard"]','aria-pressed');
  await page.tap('#ar-bot-S'); await page.waitForTimeout(500);
  const hello = await page.evaluate(()=>window.__sent.find(m=>m.t==='hello'));
  const url = await page.evaluate(()=>window.__ws.url);
  const top = await page.textContent('#ar-top');
  console.log(name, '| section visible :', visible, '| difficile choisi :', pressed, '| demande :', hello.bot, url.split('/').pop()[0], '| affichage :', top);
  if (!visible || pressed!=='true' || hello.bot!=='hard' || !/robot/.test(top) || !/\/play\/S/.test(url)) throw new Error('BOYBOT : comportement inattendu');
  if (errs.length) throw new Error(errs.join('\n'));
  await b.close();
}
console.log('boybot OK');

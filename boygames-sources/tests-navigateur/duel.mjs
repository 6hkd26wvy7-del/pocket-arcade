import { createRequire } from 'module'; const require=createRequire('/opt/npm-tools/node_modules/'); const { chromium } = require('playwright');
import fs from 'fs'; import * as BB from '/home/claude/pocket-arcade/shared/boyblocks-engine.js';
const html = fs.readFileSync('/home/claude/pocket-arcade/site/index.html','utf8');
const b=await chromium.launch(); const ctx=await b.newContext({viewport:{width:390,height:800},hasTouch:true}); const page=await ctx.newPage();
const errs=[]; page.on('pageerror',e=>errs.push(String(e.stack).slice(0,300)));
await page.addInitScript(()=>{
  window.WebSocket = class {
    constructor(url){ this.readyState=0; this.url=url; this.l={}; window.__ws=this; setTimeout(()=>{this.readyState=1; (this.l.open||[]).forEach(f=>f({}));},500); }
    addEventListener(e,f){ (this.l[e]=this.l[e]||[]).push(f); }
    close(){ this.readyState=3; }
    emit(o){ (this.l.message||[]).forEach(f=>f({data:JSON.stringify(o)})); }
    send(d){ const m=JSON.parse(d); window.__sent=(window.__sent||[]); window.__sent.push(m); window.__onClient && window.__onClient(m); }
  };
});
await page.route('**/*', r=>{ const u=r.request().url();
 if(u.startsWith('http://x.test/')) { if(u==='http://x.test/'||u.startsWith('http://x.test/?')) return r.fulfill({contentType:'text/html',body:html});
   if(u.endsWith('config.js')) return r.fulfill({contentType:'text/javascript',body:'window.ARCADE_CONFIG={SUPABASE_URL:"https://x.supabase.co",SUPABASE_ANON_KEY:"k",ARENA_URL:"wss://arena.test"};'});
   if(u.endsWith('/duel.js')) return r.fulfill({contentType:'text/javascript',body:fs.readFileSync('/home/claude/pocket-arcade/server/boyblocks-duel.js','utf8').replace('./boyblocks-engine.js','/engine.js')});
   if(u.endsWith('/engine.js')) return r.fulfill({contentType:'text/javascript',body:fs.readFileSync('/home/claude/pocket-arcade/server/boyblocks-engine.js','utf8')});
   return r.fulfill({status:404,body:''}); }
 if(u.includes('supabase.js')) return r.fulfill({contentType:'text/javascript',body:fs.readFileSync('/tmp/ft/fake5.js','utf8')}); return r.fulfill({status:200,body:'',contentType:'text/css'}); });
await page.goto('http://x.test/#arena'); await page.waitForTimeout(700);
await page.click('#ar-create-X'); await page.waitForTimeout(300);
// faux serveur dans la page
await page.evaluate(async()=>{
  const D = await import('/duel.js'); const ws=window.__ws;
  const g = D.newGame(31337); window.__g=g;
  const snap=()=>ws.emit(D.snapshot(g));
  window.__onClient=(m)=>{ if(m.t==='hello'){ ws.emit({t:'lobby',code:'XABCD',kind:'boyblocks',you:0,players:['Quentin','Zoe'],phase:'countdown'}); ws.emit({t:'countdown',ms:100,players:['Quentin','Zoe']}); setTimeout(()=>{ snap(); window.__iv=setInterval(()=>{D.step(g,250); snap();},250); },100); }
    else if(m.t==='place'){ if(D.input(g,0,m)) snap(); }
    else if(m.t==='sync'){ ws.emit(D.syncLog(g,0)); } };
  window.__bot=setInterval(()=>{ const p=g.players[1]; if(g.over||p.over)return; const BB=window.__BB; },9999);
});
await page.waitForTimeout(900);
const bx=await page.locator('#ar-screen').boundingBox(); const kx=bx.width/720, ky=bx.height/1040; const P=(x,y)=>[bx.x+x*kx,bx.y+y*ky];
console.log('canvas', bx.width|0, bx.height|0);
await page.screenshot({path:'/tmp/ft/duel-1.png'});
const g=BB.newGame(31337,{ensureFit:false}); const mouse=page.mouse; let n=0;
while(!g.over&&n<12){
  let mv=null; for(let s=0;s<3&&!mv;s++){ if(!g.pieces[s])continue; const sh=BB.PIECES[g.pieces[s].p]; for(let r=0;r<=8-sh.h&&!mv;r++)for(let c=0;c<=8-sh.w&&!mv;c++) if(BB.fits(g.grid,sh,r,c)) mv=[s,r,c,sh]; }
  const [s,r,c,sh]=mv; const sw=(720-96)/3;
  const [sx,sy]=P(48+s*sw+sw/2, 818+(1040-818-20)/2), [tx,ty]=P(48+(c+sh.w/2)*78, 148+(r+sh.h/2)*78+170);
  await mouse.move(sx,sy); await mouse.down(); await mouse.move(tx,ty,{steps:3}); await mouse.up(); BB.place(g,s,r,c); n++; await page.waitForTimeout(260);
}
// l'adversaire joue aussi
await page.evaluate(()=>{ const g=window.__g; g.ms=20000; });
await page.screenshot({path:'/tmp/ft/duel-2.png'});
const srv=await page.evaluate(()=>({me:window.__g.players[0].score,moves:window.__g.players[0].moves,sent:(window.__sent||[]).filter(m=>m.t==='place').length,syncs:(window.__sent||[]).filter(m=>m.t==='sync').length}));
console.log('serveur: score', srv.me, 'coups', srv.moves, '| envoyés', srv.sent, '| sync demandés', srv.syncs, '| local', g.score, g.moves);
// fin de partie par le temps
await page.evaluate(()=>{ window.__g.ms=119900; });
await page.waitForTimeout(900);
await page.screenshot({path:'/tmp/ft/duel-3.png'});
console.log('msg:', await page.innerText('#ar-msg'), '| rejouer visible:', await page.isVisible('#ar-again'));
console.log('errors',JSON.stringify(errs)); await b.close();

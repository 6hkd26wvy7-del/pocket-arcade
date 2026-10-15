import { createRequire } from 'module'; const require=createRequire('/opt/npm-tools/node_modules/'); const { chromium } = require('playwright');
import fs from 'fs'; import * as BB from '/home/claude/pocket-arcade/shared/boyblocks-engine.js';
const html = fs.readFileSync('/home/claude/pocket-arcade/site/index.html','utf8');
const b=await chromium.launch(); const ctx=await b.newContext({viewport:{width:390,height:800},hasTouch:true,deviceScaleFactor:2}); const page=await ctx.newPage();
const errs=[]; page.on('pageerror',e=>errs.push(String(e.stack).slice(0,400))); page.on('console',m=>{if(m.type()==='error')errs.push(m.text())});
await page.route('**/*', r=>{ const u=r.request().url();
 if(u.startsWith('http://x.test/')) { if(u==='http://x.test/'||u.startsWith('http://x.test/?')) return r.fulfill({contentType:'text/html',body:html}); if(u.endsWith('config.js')) return r.fulfill({contentType:'text/javascript',body:'window.ARCADE_CONFIG={SUPABASE_URL:"https://x.supabase.co",SUPABASE_ANON_KEY:"k"};'}); return r.fulfill({status:404,body:''}); }
 if(u.includes('supabase.js')) return r.fulfill({contentType:'text/javascript',body:fs.readFileSync('/tmp/ft/fake5.js','utf8')}); return r.fulfill({status:200,body:'',contentType:'text/css'}); });
await page.goto('http://x.test/#menu'); await page.waitForTimeout(700);
console.log('menu cards:', await page.$$eval('#game-list h3', e=>e.map(x=>x.textContent)));
await page.screenshot({path:'/tmp/ft/bb-menu.png'});
await page.goto('http://x.test/#boyblocks'); await page.waitForTimeout(900);
const box = async()=> page.locator('#bb-screen').boundingBox();
const bx=await box(); const kx=bx.width/720, ky=bx.height/1040;
const P=(x,y)=>[bx.x+x*kx, bx.y+y*ky];
await page.screenshot({path:'/tmp/ft/bb-start.png'});
const g=BB.newGame(424242,{ensureFit:true});
let n=0;
const mouse=page.mouse;
while(!g.over && n<400){
  let mv=null;
  for(let s=0;s<3&&!mv;s++){ if(!g.pieces[s])continue; const sh=BB.PIECES[g.pieces[s].p];
    for(let r=0;r<=8-sh.h&&!mv;r++)for(let c=0;c<=8-sh.w&&!mv;c++) if(BB.fits(g.grid,sh,r,c)) mv=[s,r,c,sh]; }
  if(!mv)break;
  const [s,r,c,sh]=mv; const sw=(720-96)/3;
  const [sx,sy]=P(48+s*sw+sw/2, 818+(1040-818-20)/2);
  const [tx,ty]=P(48+(c+sh.w/2)*78, 148+(r+sh.h/2)*78+170);
  await mouse.move(sx,sy); await mouse.down(); await mouse.move((sx+tx)/2,(sy+ty)/2,{steps:2}); await mouse.move(tx,ty,{steps:2}); 
  if(n==3) await page.screenshot({path:'/tmp/ft/bb-drag.png'});
  await mouse.up();
  BB.place(g,s,r,c); n++;
  if(n%6==0) await page.waitForTimeout(30);
}
await page.waitForTimeout(1200);
const st=await page.evaluate(()=>window.__fin);
console.log('moves joués', n, 'score attendu', g.score, 'over', g.over);
console.log('envoyé au serveur:', st && st.p_moves.length, 'coups, run', st && st.p_run, 'identiques:', JSON.stringify(st&&st.p_moves)===JSON.stringify(g.log));
await page.waitForTimeout(500); console.log('msg:', await page.innerText('#bb-msg'));
await page.screenshot({path:'/tmp/ft/bb-over.png'});
await page.click('#bb-screen'); await page.waitForTimeout(500);
console.log('après rejeu, calls:', (await page.evaluate(()=>window.__calls.filter(c=>/boyblocks/.test(c)).length)));
await page.goto('http://x.test/#scores'); await page.waitForTimeout(600);
console.log('options classement:', await page.$$eval('#lb-game option', e=>e.map(x=>x.textContent)));
console.log('errors',JSON.stringify(errs)); await b.close();

// Site TEST (test/index.html) dans WebKit (moteur de Safari) avec un écran d'iPhone : chaque page s'ouvre
// sans erreur JS, et une partie de BoyBlocks se joue au doigt jusqu'au score vérifié.
import { createRequire } from 'module'; const require=createRequire(import.meta.url); const { webkit, devices } = require('playwright');
const ROOT=new URL('../../', import.meta.url).pathname, FT=new URL('./', import.meta.url).pathname;
import fs from 'fs'; import * as BB from '../../shared/boyblocks-engine.js';
fs.mkdirSync(FT+'captures',{recursive:true});
const html = fs.readFileSync(ROOT+'test/index.html','utf8');
const b=await webkit.launch(); const ctx=await b.newContext({...devices['iPhone 13']}); const page=await ctx.newPage();
await page.addInitScript(()=>{ window.__synced=1; });
const errs=[]; page.on('pageerror',e=>errs.push(String(e).slice(0,300)));
await page.route('**/*', r=>{ const u=r.request().url();
 if(u.startsWith('http://x.test/')) { if(u==='http://x.test/'||u.startsWith('http://x.test/?')) return r.fulfill({contentType:'text/html',body:html}); if(u.endsWith('config.js')||u.endsWith('config.test.js')) return r.fulfill({contentType:'text/javascript',body:'window.ARCADE_CONFIG={SUPABASE_URL:"https://x.supabase.co",SUPABASE_ANON_KEY:"k"};'}); return r.fulfill({status:404,body:''}); }
 if(u.includes('supabase.js')) return r.fulfill({contentType:'text/javascript',body:fs.readFileSync(FT+'fake5.js','utf8')}); return r.fulfill({status:200,body:'',contentType:'text/css'}); });
for (const h of ['menu','scores','amis','compte','snake','blocks','space','arena']) {
  await page.goto('http://x.test/#'+h); await page.waitForTimeout(500);
  const w = await page.evaluate(()=>document.documentElement.scrollWidth);
  console.log('page', h, w <= 390 ? 'largeur ok' : 'DÉBORDE ('+w+'px)');
}
await page.screenshot({path:FT+'captures/iphone-arena.png'});
await page.goto('http://x.test/#boyblocks'); await page.waitForTimeout(900);
const sel = await page.evaluate(()=>{
  const ev=new Event('selectstart',{bubbles:true,cancelable:true}); document.getElementById('bb-msg').dispatchEvent(ev);
  const cm=new Event('contextmenu',{bubbles:true,cancelable:true}); document.getElementById('bb-screen').dispatchEvent(cm);
  const ta=document.createElement('textarea'); document.getElementById('bug-card').append(ta);
  const ev2=new Event('selectstart',{bubbles:true,cancelable:true}); ta.dispatchEvent(ev2);
  const us=getComputedStyle(document.getElementById('bb-msg')).webkitUserSelect, ut=getComputedStyle(ta).webkitUserSelect; ta.remove();
  return { ingame: document.body.classList.contains('ingame'), texteBloque: ev.defaultPrevented && us==='none', menuBloque: cm.defaultPrevented, saisieLibre: !ev2.defaultPrevented && ut!=='none' };
});
console.log('tactile en jeu :', JSON.stringify(sel), (sel.ingame && sel.texteBloque && sel.menuBloque && sel.saisieLibre) ? 'protection ok' : 'PROTECTION KO');
const bx=await page.locator('#bb-screen').boundingBox(); const kx=bx.width/720, ky=bx.height/1040; const P=(x,y)=>[bx.x+x*kx, bx.y+y*ky];
const g=BB.newGame(424242,{ensureFit:true,rules:2}); let n=0;
while(!g.over && n<400){
  let mv=null;
  for(let s=0;s<3&&!mv;s++){ if(!g.pieces[s])continue; const sh=BB.PIECES[g.pieces[s].p];
    for(let r=0;r<=8-sh.h&&!mv;r++)for(let c=0;c<=8-sh.w&&!mv;c++) if(BB.fits(g.grid,sh,r,c)) mv=[s,r,c,sh]; }
  if(!mv)break;
  const [s,r,c,sh]=mv; const sw=(720-96)/3;
  const [sx,sy]=P(48+s*sw+sw/2, 818+(1040-818-20)/2), [tx,ty]=P(48+(c+sh.w/2)*78, 148+(r+sh.h/2)*78+170);
  await page.mouse.move(sx,sy); await page.mouse.down(); await page.mouse.move(tx,ty,{steps:3}); await page.mouse.up();
  BB.place(g,s,r,c); n++;
}
await page.waitForTimeout(1200);
const fin=await page.evaluate(()=>window.__fin);
console.log('boyblocks coups', n, '| envoyés identiques:', JSON.stringify(fin&&fin.p_moves)===JSON.stringify(g.log), '|', await page.innerText('#bb-msg'));
await page.screenshot({path:FT+'captures/iphone-boyblocks.png'});
console.log('errors',JSON.stringify(errs)); await b.close();

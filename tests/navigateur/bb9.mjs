// BoyBlocks 9x9 (essai) : choix de la grille, partie complète au doigt, coups envoyés = moteur, aimant de placement,
// retour au 8x8 quand l'équipe désactive l'essai.
import { createRequire } from 'module'; const require=createRequire(import.meta.url); const { webkit, devices } = require('playwright');
const ROOT=new URL('../../', import.meta.url).pathname, FT=new URL('./', import.meta.url).pathname;
import fs from 'fs'; import * as BB from '../../shared/boyblocks-engine.js';
fs.mkdirSync(FT+'captures',{recursive:true});
const html = fs.readFileSync(ROOT+'test/index.html','utf8');
const b=await webkit.launch();
async function open(noNine){
  const page=await (await b.newContext({...devices['iPhone 13']})).newPage();
  await page.addInitScript((n)=>{ window.__synced=1; window.__noNine=n; try{ localStorage.setItem('boygames-bb-size','9'); }catch(e){} }, noNine);
  const errs=[]; page.on('pageerror',e=>errs.push(String(e).slice(0,300)));
  await page.route('**/*', r=>{ const u=r.request().url();
   if(u.startsWith('http://x.test/')) { if(u==='http://x.test/'||u.startsWith('http://x.test/?')) return r.fulfill({contentType:'text/html',body:html}); if(u.includes('config')) return r.fulfill({contentType:'text/javascript',body:'window.ARCADE_CONFIG={SUPABASE_URL:"https://x.supabase.co",SUPABASE_ANON_KEY:"k"};'}); return r.fulfill({status:404,body:''}); }
   if(u.includes('supabase.js')) return r.fulfill({contentType:'text/javascript',body:fs.readFileSync(FT+'fake5.js','utf8')}); return r.fulfill({status:200,body:'',contentType:'text/css'}); });
  return { page, errs };
}
let { page, errs } = await open(false);
await page.goto('http://x.test/#menu'); await page.waitForTimeout(700);
await page.goto('http://x.test/#boyblocks'); await page.waitForTimeout(1000);
console.log('bouton grille :', await page.innerText('#bb-size'), '| partie demandée :', JSON.stringify(await page.evaluate(()=>window.__run)));
const bx=await page.locator('#bb-screen').boundingBox(); const kx=bx.width/720, ky=bx.height/1040; const P=(x,y)=>[bx.x+x*kx, bx.y+y*ky];
const CELL=69, BX=(720-9*69)/2, BY=148;
const g=BB.newGame(515151,{ensureFit:true,rules:2,size:9}); let n=0, decales=0;
while(!g.over && n<300){
  let mv=null;
  for(let s=0;s<3&&!mv;s++){ if(!g.pieces[s])continue; const sh=BB.PIECES[g.pieces[s].p];
    for(let r=0;r<=9-sh.h&&!mv;r++)for(let c=0;c<=9-sh.w&&!mv;c++) if(BB.fits(g.grid,sh,r,c)) mv=[s,r,c,sh]; }
  if(!mv)break;
  const [s,r,c,sh]=mv; const sw=(720-2*BX)/3;
  // un doigt imprécis : décalage d'un tiers de case une fois sur deux (l'aimant doit corriger)
  const off = n % 2 ? 0.33 * CELL : 0; if (off) decales++;
  const [sx,sy]=P(BX+s*sw+sw/2, 818+(1040-818-20)/2), [tx,ty]=P(BX+(c+sh.w/2)*CELL+off, BY+(r+sh.h/2)*CELL+170+off);
  await page.mouse.move(sx,sy); await page.mouse.down(); await page.mouse.move(tx,ty,{steps:3}); await page.mouse.up();
  BB.place(g,s,r,c); n++;
}
await page.waitForTimeout(1200);
const fin=await page.evaluate(()=>window.__fin);
console.log('9x9 : coups', n, '(dont', decales, 'imprécis) | envoyés identiques:', JSON.stringify(fin&&fin.p_moves)===JSON.stringify(g.log), '| score', g.score);
await page.screenshot({path:FT+'captures/boyblocks-9x9.png'});
console.log('errors', JSON.stringify(errs));
({ page, errs } = await open(true));
await page.goto('http://x.test/#menu'); await page.waitForTimeout(700);
await page.goto('http://x.test/#boyblocks'); await page.waitForTimeout(1000);
console.log('essai désactivé : bouton caché', !(await page.isVisible('#bb-size')), '| partie 8x8 :', JSON.stringify(await page.evaluate(()=>window.__run)));
console.log('errors', JSON.stringify(errs));
await b.close();

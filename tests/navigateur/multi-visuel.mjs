// Snake 1V1 et Space Attack co-op : rendu harmonisé avec le solo (pommes, quadrillage, vaisseaux), sans erreur.
import { createRequire } from 'module'; const require=createRequire(import.meta.url); const { chromium } = require('playwright');
import fs from 'fs';
const ROOT=new URL('../../', import.meta.url).pathname, FT=new URL('./', import.meta.url).pathname; fs.mkdirSync(FT+'captures',{recursive:true});
const html = fs.readFileSync(ROOT+'site/index.html','utf8');
const b=await chromium.launch(); const ctx=await b.newContext({viewport:{width:390,height:800},hasTouch:true}); const page=await ctx.newPage();
await page.addInitScript(()=>{ window.__synced=1;
  window.WebSocket = class { constructor(){ this.readyState=0; this.l={}; window.__ws=this; setTimeout(()=>{this.readyState=1;(this.l.open||[]).forEach(f=>f({}));},300); }
    addEventListener(e,f){ (this.l[e]=this.l[e]||[]).push(f); } close(){ this.readyState=3; }
    emit(o){ (this.l.message||[]).forEach(f=>f({data:JSON.stringify(o)})); } send(d){ window.__onClient && window.__onClient(JSON.parse(d)); } }; });
const errs=[]; page.on('pageerror',e=>errs.push(String(e.stack).slice(0,300)));
await page.route('**/*', r=>{ const u=r.request().url();
  if(u.startsWith('http://x.test/')) { if(u==='http://x.test/'||u.startsWith('http://x.test/?')) return r.fulfill({contentType:'text/html',body:html});
    if(u.endsWith('config.js')) return r.fulfill({contentType:'text/javascript',body:'window.ARCADE_CONFIG={SUPABASE_URL:"https://x.supabase.co",SUPABASE_ANON_KEY:"k",ARENA_URL:"wss://arena.test"};'});
    return r.fulfill({status:404,body:''}); }
  if(u.includes('supabase.js')) return r.fulfill({contentType:'text/javascript',body:fs.readFileSync(FT+'fake5.js','utf8')}); return r.fulfill({status:200,body:'',contentType:'text/css'}); });
async function room(btn, kind, state){
  await page.goto('http://x.test/?'+kind+'#arena'); await page.waitForTimeout(600);
  await page.evaluate(([kind,state])=>{ window.__onClient=(m)=>{ if(m.t==='hello'){ const ws=window.__ws;
    ws.emit({t:'lobby',code:'ZABCD',kind,you:0,players:['Quentin','Zoe'],phase:'countdown'}); ws.emit({t:'countdown',ms:50,players:['Quentin','Zoe']});
    setTimeout(()=>ws.emit(Object.assign({t:'state',kind},state)),80); } }; },[kind,state]);
  await page.click(btn); await page.waitForTimeout(900);
  return page.evaluate(()=>{ const c=document.getElementById('ar-screen'), x=c.getContext('2d'), d=x.getImageData(0,0,c.width,c.height).data; let red=0;
    for(let i=0;i<d.length;i+=4) if(d[i]>200&&d[i+1]<100&&d[i+2]<100) red++; return {red, w:c.width}; });
}
const body=(x,y)=>[0,1,2,3].map(k=>({x:x-k,y}));
const sn=await room('#ar-create-S','snake',{players:[{body:body(8,5),score:3,alive:true},{body:body(15,15),score:1,alive:true}],food:[{x:4,y:10},{x:20,y:3}],over:false});
await page.screenshot({path:FT+'captures/snake-1v1.png'});
if(sn.red<40) throw new Error('pommes rouges absentes du Snake 1V1 : '+sn.red);
const sp=await room('#ar-create-P','space',{score:120,wave:2,ships:[{x:30,lives:3,invuln:false,power:{triple:6000,shield:9000},picked:'triple'},{x:100,lives:2,invuln:false}],enemies:[[20,40],[40,40]],bullets:[[36,150],[104,140,1]],drops:[[70,100,'laser']],shots:[],over:false});
await page.screenshot({path:FT+'captures/space-coop.png'});
const bonusPx=await page.evaluate(()=>{ const c=document.getElementById('ar-screen'), d=c.getContext('2d').getImageData(0,0,c.width,c.height).data; let pink=0,sky=0;
  for(let i=0;i<d.length;i+=4){ if(d[i]===0xF4&&d[i+1]===0x72&&d[i+2]===0xB6) pink++; if(d[i]===0x38&&d[i+1]===0xBD&&d[i+2]===0xF8) sky++; } return {pink,sky}; });
if(bonusPx.pink<10||bonusPx.sky<10) throw new Error('bonus co-op non dessines : '+JSON.stringify(bonusPx));
if(sp.red<30) throw new Error('vaisseaux/cœurs absents du Space co-op : '+sp.red);
if(errs.length) throw new Error(errs.join('\n'));
console.log('multi-visuel OK', JSON.stringify({sn,sp})); await b.close();

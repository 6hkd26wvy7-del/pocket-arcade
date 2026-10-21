// Publicités AdSense (src/pub.js) sur iPhone simulé : aucune requête Google tant que ce n'est pas activé et approuvé ;
// bandeau de consentement avant tout script d'annonces ; refus = aucune annonce ; jamais d'annonce en partie.
// Les scripts Google sont remplacés par des faux : aucune vraie requête ne sort.
// Seul : python3 -I make_test_release.py puis node pub.mjs (PUB_BROWSER=chromium si WebKit n'est pas installé).
import { createRequire } from 'module'; const require=createRequire(import.meta.url); const pw = require('playwright');
const ROOT=new URL('../../', import.meta.url).pathname, FT=new URL('./', import.meta.url).pathname;
import fs from 'fs';
const html = fs.readFileSync(ROOT+'test/index.html','utf8');
const engine = process.env.PUB_BROWSER === 'chromium' ? pw.chromium : pw.webkit;
const b = await engine.launch();
const ON = 'window.BG_PUB_CONFIG={enabled:true,approved:true,publisherId:"ca-pub-1234567890123456",slots:{home:"1111111111",scores:"2222222222",shop:""},underAgeOfConsent:true};';
const SRV = {ads:{enabled:true,provider:'adsense',slots:{home:true,scores:true,shop:true}},rewarded:{enabled:false,continue_max:0,games:[]},premium:{enabled:false}};
// Faux bandeau Google : expose __tcfapi ; le choix est simulé par window.__choose(true|false).
const FAKE_CMP = `(function(){var ls=[],tc={gdprApplies:true,eventStatus:'cmpuishown',purpose:{consents:{}}};
 window.__tcfapi=function(cmd,v,cb){ if(cmd==='addEventListener'){ ls.push(cb); cb(tc,true); } };
 window.__choose=function(yes){ tc={gdprApplies:true,eventStatus:'useractioncomplete',purpose:{consents:yes?{1:true}:{}}}; ls.forEach(function(f){f(tc,true);}); };
 window.googlefc={callbackQueue:{push:function(o){ window.__revoked=1; }}}; })();`;
let fail = 0; const check = (label, v) => { console.log(label, v); if (v !== true) fail++; };
async function open(cfg, monet, premium){
  const ctx=await b.newContext({...pw.devices['iPhone 13']}); const page=await ctx.newPage();
  await page.addInitScript(([m,p])=>{ window.__synced=1; window.__monet=m; window.__premium=p; }, [monet, !!premium]);
  const errs=[], google=[]; page.on('pageerror',e=>errs.push(String(e).slice(0,200)));
  await page.route('**/*', r=>{ const u=r.request().url();
   if(/fundingchoicesmessages\.google\.com/.test(u)) { google.push('cmp'); return r.fulfill({contentType:'text/javascript',body:FAKE_CMP}); }
   if(/googlesyndication|doubleclick|googletagservices|adservice\.google/.test(u)) { google.push('ads'); return r.fulfill({contentType:'text/javascript',body:'window.__adsLoaded=1;'}); }
   if(u.startsWith('http://x.test/')) {
     if(u==='http://x.test/'||u.startsWith('http://x.test/?')) return r.fulfill({contentType:'text/html',body:html});
     if(u.includes('reglages-pub.js')) return r.fulfill({contentType:'text/javascript',body: cfg || fs.readFileSync(ROOT+'test/reglages-pub.js','utf8')});
     if(u.includes('pub.js')) return r.fulfill({contentType:'text/javascript',body:fs.readFileSync(ROOT+'test/pub.js','utf8')});
     if(u.includes('config')) return r.fulfill({contentType:'text/javascript',body:'window.ARCADE_CONFIG={SUPABASE_URL:"https://x.supabase.co",SUPABASE_ANON_KEY:"k"};'});
     return r.fulfill({status:404,body:''}); }
   if(u.includes('supabase.js')) return r.fulfill({contentType:'text/javascript',body:fs.readFileSync(FT+'fake5.js','utf8')});
   return r.fulfill({status:200,body:'',contentType:'text/css'}); });
  return { page, errs, google, ctx };
}
const visibleSlots = (page) => page.evaluate(()=>[...document.querySelectorAll('.ad-slot')].filter(s=>s.offsetParent!==null).length);

// 1. Réglages livrés (désactivés), même si le serveur demande AdSense : rien de Google, aucun emplacement, pas de lien cookies.
let { page, errs, google, ctx } = await open(null, SRV);
await page.goto('http://x.test/#menu'); await page.waitForTimeout(900);
check('livré : aucune requête Google :', google.length === 0);
check('livré : aucun emplacement visible :', (await visibleSlots(page)) === 0);
check('livré : lien cookies caché :', !(await page.isVisible('#pub-consent')));
check('livré : lien mentions légales :', await page.isVisible('footer a[href="mentions-legales.html"]'));
console.log('errors', JSON.stringify(errs)); await ctx.close();

// 2. Activé mais pas approuvé : rien.
({ page, errs, google, ctx } = await open(ON.replace('approved:true','approved:false'), SRV));
await page.goto('http://x.test/#menu'); await page.waitForTimeout(900);
check('non approuvé : aucune requête Google :', google.length === 0 && (await visibleSlots(page)) === 0);
console.log('errors', JSON.stringify(errs)); await ctx.close();

// 3. Activé et approuvé : bandeau d'abord, annonces seulement après acceptation, jamais en partie.
({ page, errs, google, ctx } = await open(ON, SRV));
await page.goto('http://x.test/#menu'); await page.waitForTimeout(900);
check('avant choix : bandeau chargé, pas de script d\'annonces :', google.join() === 'cmp' && !(await page.evaluate(()=>window.__adsLoaded)));
check('avant choix : aucun emplacement visible :', (await visibleSlots(page)) === 0);
check('avant choix : lien « gérer les cookies » :', await page.isVisible('#pub-consent'));
await page.evaluate(()=>window.__choose(true)); await page.waitForTimeout(400);
check('accepté : script d\'annonces chargé :', google.includes('ads'));
const ins = await page.evaluate(()=>{ const i=document.querySelector('.ad-slot[data-slot="home"] ins.adsbygoogle'); return i && { client:i.getAttribute('data-ad-client'), slot:i.getAttribute('data-ad-slot'), tfua:i.getAttribute('data-tag-for-under-age-of-consent'), h:i.style.height }; });
check('accepté : annonce accueil, non personnalisée, 100 px :', !!ins && ins.client==='ca-pub-1234567890123456' && ins.slot==='1111111111' && ins.tfua==='1' && ins.h==='100px');
await page.goto('http://x.test/#scores'); await page.waitForTimeout(700);
check('classements : annonce présente :', await page.evaluate(()=>!!document.querySelector('.ad-slot[data-slot="scores"] ins.adsbygoogle')));
await page.goto('http://x.test/#boutique'); await page.waitForTimeout(700);
check('boutique : bloc non renseigné = rien :', (await visibleSlots(page)) === 0);
for (const g of ['snake','space','boyblocks','blocks','arena']) {
  await page.goto('http://x.test/#'+g); await page.waitForTimeout(500);
  const n = await page.evaluate(()=>[...document.querySelectorAll('ins.adsbygoogle')].filter(i=>i.offsetParent!==null).length + [...document.querySelectorAll('.ad-slot')].filter(s=>s.offsetParent!==null).length);
  check('en jeu ('+g+') : aucune annonce visible :', n === 0);
}
await page.goto('http://x.test/#menu'); await page.waitForTimeout(500);
await page.click('#pub-consent'); await page.waitForTimeout(200);
check('gérer les cookies : rouvre le choix :', await page.evaluate(()=>window.__revoked===1));
console.log('errors', JSON.stringify(errs)); await ctx.close();

// 4. Refus : aucun script d'annonces, aucun emplacement, le site marche pareil.
({ page, errs, google, ctx } = await open(ON, SRV));
await page.goto('http://x.test/#menu'); await page.waitForTimeout(900);
await page.evaluate(()=>window.__choose(false)); await page.waitForTimeout(400);
check('refusé : pas de script d\'annonces :', !google.includes('ads') && (await visibleSlots(page)) === 0);
check('refusé : jeux toujours affichés :', (await page.locator('#game-list').innerText()).length > 0);
console.log('errors', JSON.stringify(errs)); await ctx.close();

// 5. Premium : rien, même approuvé.
({ page, errs, google, ctx } = await open(ON, SRV, true));
await page.goto('http://x.test/#menu'); await page.waitForTimeout(900);
check('premium : aucune requête Google :', google.length === 0);
console.log('errors', JSON.stringify(errs)); await ctx.close();

await b.close();
console.log(fail ? fail + ' vérification(s) en échec' : 'pub OK');
process.exit(fail ? 1 : 0);

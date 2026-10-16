// iPhone (WebKit) : défilement hors partie, fiche profil depuis le classement (ami / défi), espace bêta-testeur, suivi bêta + CSV.
import { createRequire } from 'module'; const require=createRequire(import.meta.url); const { webkit, devices } = require('playwright');
import fs from 'fs';
const ROOT=new URL('../../', import.meta.url).pathname, FT=new URL('./', import.meta.url).pathname; fs.mkdirSync(FT+'captures',{recursive:true});
const html = fs.readFileSync(ROOT+'site/index.html','utf8');
const fail = (m) => { throw new Error(m); };
const b=await webkit.launch(); const ctx=await b.newContext({...devices['iPhone 13'], acceptDownloads:true}); const page=await ctx.newPage();
await page.addInitScript(()=>{ window.__synced=1; window.navigator.standalone=true;   // comme l'appli installée (PWA)
  window.WebSocket = class { constructor(url){ this.url=url; this.readyState=0; this.l={}; window.__ws=this; } addEventListener(e,f){ (this.l[e]=this.l[e]||[]).push(f); } close(){} send(){} }; });
const errs=[]; page.on('pageerror',e=>errs.push(String(e.stack).slice(0,300)));
await page.route('**/*', r=>{ const u=r.request().url();
  if(u.startsWith('http://x.test/')) { if(u==='http://x.test/'||u.startsWith('http://x.test/?')) return r.fulfill({contentType:'text/html',body:html});
    if(u.endsWith('config.js')) return r.fulfill({contentType:'text/javascript',body:'window.ARCADE_CONFIG={SUPABASE_URL:"https://x.supabase.co",SUPABASE_ANON_KEY:"k",ARENA_URL:"wss://arena.test"};'});
    return r.fulfill({status:404,body:''}); }
  if(u.includes('supabase.js')) return r.fulfill({contentType:'text/javascript',body:fs.readFileSync(FT+'fake5.js','utf8')}); return r.fulfill({status:200,body:'',contentType:'text/css'}); });
// effective touch-action : aucun ancêtre ne doit bloquer le défilement hors partie
const blocked = (sel) => page.evaluate((sel)=>{ let e=document.querySelector(sel); const out=[]; while(e){ const ta=getComputedStyle(e).touchAction; if(ta==='none'||ta==='pan-x') out.push((e.id||e.tagName)+':'+ta); e=e.parentElement; } return out; }, sel);
// 1. défilement
await page.goto('http://x.test/#menu'); await page.waitForTimeout(700);
const homeB = await blocked('#game-list');
await page.goto('http://x.test/?a#arena'); await page.waitForTimeout(600);
const botB = await blocked('#ar-bot-S'); const lobbyB = await blocked('#ar-bot');
await page.evaluate(()=>window.scrollTo(0, 0)); const y0 = await page.evaluate(()=>window.scrollY);
await page.evaluate(()=>window.scrollBy(0, 400)); const y1 = await page.evaluate(()=>window.scrollY);
console.log('défilement | accueil bloqué :', homeB.length ? homeB : 'non', '| page BOYBOT bloquée :', botB.length ? botB : 'non', '| la page défile :', y1 > y0);
if (homeB.length || botB.length || lobbyB.length || !(y1 > y0)) fail('défilement encore bloqué');
await page.tap('#ar-bot-S'); await page.waitForTimeout(300);
const gameB = await blocked('#ar-screen'), ingame = await page.evaluate(()=>document.body.classList.contains('ingame'));
if (!gameB.length || !ingame) fail('pendant la partie, les gestes doivent rester bloqués');
// 2. fiche profil depuis le classement
await page.goto('http://x.test/?s#scores'); await page.waitForTimeout(700);
await page.tap('#lb-list li >> text=Max'); await page.waitForTimeout(400);
const sheet1 = await page.textContent('#pf-sheet');
if (!/Record .* : 90 \(n°2/.test(sheet1) || /@|e-mail/i.test(sheet1)) fail('fiche Max inattendue : ' + sheet1);
await page.screenshot({path:FT+'captures/profil-classement-iphone.png'});
await page.tap('#pf-sheet >> text=AJOUTER EN AMI'); await page.waitForTimeout(200);
const req = await page.evaluate(()=>window.__calls.filter(c=>c.startsWith('send_friend_request')));
await page.tap('#pf-sheet >> text=FERMER'); await page.waitForTimeout(200);
const closed = await page.isHidden('#pf-modal');
await page.tap('#lb-list li >> text=Zoe'); await page.waitForTimeout(400);
await page.tap('#pf-sheet >> text=DÉFIER'); await page.waitForTimeout(150);
await page.tap('#pf-sheet button:text-is("SNAKE")'); await page.waitForTimeout(700);
const dm = await page.evaluate(()=>window.__calls.filter(c=>c.startsWith('send_message')).pop()||'');
const room = await page.evaluate(()=>window.__ws && window.__ws.url || '');
const code = (dm.match(/code ([A-Z0-9]+)/)||[])[1];
console.log('profils | demande d\'ami :', req.length, '| fermeture :', closed, '| défi envoyé :', !!code, '| salle ouverte :', room.split('/').pop(), '| même code :', room.endsWith('/'+code));
if (req.length !== 1 || !closed || !code || !room.endsWith('/'+code) || code[0] !== 'S') fail('défi / ami');
// 3. espace bêta-testeur
await page.goto('http://x.test/?b#beta'); await page.waitForTimeout(700);
const pct0 = await page.textContent('.bt-pct'), evi = await page.textContent('.bt-m >> nth=1');
await page.tap('.bt-m >> nth=1 >> text=Réussi ✓'); await page.waitForTimeout(200);
await page.tap('.bt-m >> nth=3 >> text=Problème ⚠'); await page.waitForTimeout(200);
const noteVisible = await page.isVisible('.bt-m >> nth=3 >> textarea');
await page.fill('.bt-m >> nth=3 >> textarea', 'Un ennemi traverse le vaisseau'); await page.waitForTimeout(1100);
const pct1 = await page.textContent('.bt-pct'), saved = await page.evaluate(()=>window.__beta.missions);
await page.screenshot({path:FT+'captures/espace-beta-iphone.png'});
await page.tap('text=🐞 SIGNALER UN BUG'); await page.waitForTimeout(300); const bugOpen = await page.isVisible('#bug-modal');
console.log('espace bêta | progression :', pct0, '→', pct1, '| preuve Snake :', /12 score/.test(evi), '| note :', noteVisible, saved.space && saved.space.note, '| bug :', bugOpen);
if (pct0.trim() !== '0 %' || pct1.trim() !== '18 %' || saved.snake.status !== 'reussi' || saved.space.note !== 'Un ennemi traverse le vaisseau' || !bugOpen) fail('espace bêta');
if (saved.snake && /auto/.test(JSON.stringify(saved))) fail('validation automatique');
// 4. suivi bêta (équipe) + CSV
await page.addInitScript(()=>{ window.__role='founder'; window.__overview={version:1,codes:['compte','snake'],required:['compte','snake'],beta_on:false,testers:[
  {pseudo:'Joh',member:true,missions:{compte:'reussi',snake:'probleme'},notes:{snake:'trop rapide; "vraiment"'},survey:'2026-10-16T10:00:00Z',bugs:2,evidence:{snake:4},eligible:true,badge:false,decision:null},
  {pseudo:'Zed',member:false,missions:{compte:'reussi'},notes:{},survey:null,bugs:0,evidence:{},eligible:false,badge:false,decision:null}]}; });
await page.goto('http://x.test/?su#suivi'); await page.waitForTimeout(800);
const kp = await page.$$eval('.rt-kpi b', e=>e.map(x=>x.textContent));
const [dl] = await Promise.all([page.waitForEvent('download'), page.tap('text=EXPORT CSV')]);
const csv = fs.readFileSync(await dl.path(), 'utf8');
await page.tap('summary >> text=Joh'); page.once('dialog', d=>d.accept()); await page.tap('text=VALIDER LE BADGE'); await page.waitForTimeout(300);
const val = await page.evaluate(()=>window.__validated);
await page.tap('summary >> text=Zed'); const zedDisabled = await page.isDisabled('details:has(summary:text("Zed")) >> text=VALIDER LE BADGE');
console.log('suivi | chiffres :', kp.join(' / '), '| CSV lignes :', csv.trim().split('\n').length, '| validation :', val && val.p_pseudo, val && val.p_decision, '| non éligible bloqué :', zedDisabled);
if (csv.split('\n').length < 3 || !/"snake: trop rapide; ""vraiment"""/.test(csv) || !val || val.p_pseudo !== 'Joh' || !zedDisabled) fail('suivi');
if (errs.length) fail(errs.join('\n'));
await b.close(); console.log('beta-profils OK');

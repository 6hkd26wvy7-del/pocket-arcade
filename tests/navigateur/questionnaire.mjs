// Questionnaire bêta : parcours au doigt (iPhone WebKit + Chromium), jeux non testés sautés, envoi, modification ;
// puis page « Retours bêta » (statistiques, problèmes les plus signalés, commentaires).
import { createRequire } from 'module'; const require=createRequire(import.meta.url); const { chromium, webkit, devices } = require('playwright');
import fs from 'fs';
const ROOT=new URL('../../', import.meta.url).pathname, FT=new URL('./', import.meta.url).pathname; fs.mkdirSync(FT+'captures',{recursive:true});
const html = fs.readFileSync(ROOT+'site/index.html','utf8');
const fail = (m) => { throw new Error(m); };
for (const [name, engine, opts] of [['webkit-iphone', webkit, devices['iPhone 13']], ['chromium', chromium, {viewport:{width:390,height:800},hasTouch:true}]]) {
  const b=await engine.launch(); const ctx=await b.newContext(opts); const page=await ctx.newPage();
  await page.addInitScript(()=>{ window.__synced=1; });
  const errs=[]; page.on('pageerror',e=>errs.push(String(e.stack).slice(0,300)));
  await page.route('**/*', r=>{ const u=r.request().url();
    if(u.startsWith('http://x.test/')) { if(u==='http://x.test/'||u.startsWith('http://x.test/?')) return r.fulfill({contentType:'text/html',body:html});
      if(u.endsWith('config.js')) return r.fulfill({contentType:'text/javascript',body:'window.ARCADE_CONFIG={SUPABASE_URL:"https://x.supabase.co",SUPABASE_ANON_KEY:"k"};'});
      return r.fulfill({status:404,body:''}); }
    if(u.includes('supabase.js')) return r.fulfill({contentType:'text/javascript',body:fs.readFileSync(FT+'fake5.js','utf8')}); return r.fulfill({status:200,body:'',contentType:'text/css'}); });
  await page.goto('http://x.test/#menu'); await page.waitForTimeout(800);
  const nudge = await page.isVisible('#menu-survey'); if (!nudge) fail('rappel absent de l\'accueil');
  await page.tap('#menu-survey'); await page.waitForTimeout(400);
  // parcours : Snake et Space « pas encore », le reste « oui » ; 1re option des questions simples, 2e option des multiples
  const notTested = ['Snake', 'Space Attack'];
  for (let i = 0; i < 60; i++) {
    const sec = (await page.textContent('#sv-body .sv-sec')) || '';
    if (/Dernière étape/.test(sec)) break;
    const hint = (await page.textContent('#sv-body .sv-hint')) || '';
    if (/sont passées/.test(hint)) { await page.tap(notTested.some(g => sec === g) ? '.sv-opt >> nth=1' : '.sv-opt >> nth=0'); await page.waitForTimeout(350); if (i === 0) await page.screenshot({path:FT+'captures/questionnaire-'+name+'.png'}); continue; }
    if (/Plusieurs/.test(hint)) { await page.tap('.sv-opt >> nth=1'); await page.waitForTimeout(80); if (i === 1) await page.screenshot({path:FT+'captures/questionnaire-'+name+'.png'}); await page.tap('text=SUIVANT →'); await page.waitForTimeout(120); continue; }
    await page.tap('.sv-opt >> nth=0'); await page.waitForTimeout(350);
  }
  await page.fill('#sv-body textarea', 'Super bêta, bravo !'); await page.tap('text=ENVOYER'); await page.waitForTimeout(500);
  const sv = await page.evaluate(()=>window.__survey);
  const qs = Object.keys(sv.answers).filter(k=>k.startsWith('q_'));
  if (!sv.completed_at) fail('questionnaire non envoyé');
  if (qs.some(k=>/^q_(snake|space)/.test(k))) fail('section non testée pas sautée : '+qs);
  if (sv.answers.g_snake !== 'non' || sv.answers.g_boybot !== 'oui') fail('portes mal enregistrées');
  if (!/Merci/.test(await page.textContent('#sv-body'))) fail('écran de remerciement absent');
  // modification : la réponse précédente est pré-cochée, on la change
  await page.tap('text=MODIFIER MES RÉPONSES'); await page.waitForTimeout(300);
  const pre = await page.getAttribute('.sv-opt >> nth=0', 'aria-pressed'); if (pre !== 'true') fail('réponse précédente non pré-cochée');
  await page.tap('.sv-opt >> nth=2'); await page.waitForTimeout(1200);
  const changed = await page.evaluate(()=>window.__survey.answers.q_inscription);
  const saves = await page.evaluate(()=>window.__saves||0);
  await page.tap('text=ENREGISTRER').catch(()=>{}); await page.evaluate(()=>{ location.hash='#menu'; }); await page.waitForTimeout(600);
  const nudgeAfter = await page.evaluate(()=>!document.getElementById('menu-survey').hidden);
  console.log(name, '| questions répondues :', qs.length, '| sections sautées : snake, space | modifié :', changed, '| sauvegardes auto :', saves, '| rappel après envoi :', nudgeAfter);
  if (changed !== 'complique') fail('modification non enregistrée');
  if (saves < 2) fail('sauvegarde automatique absente'); if (nudgeAfter) fail('rappel encore affiché après envoi');
  if (errs.length) fail(errs.join('\n'));
  await b.close();
}
// ---- Retours bêta (équipe) ----
{
  const b=await webkit.launch(); const ctx=await b.newContext(devices['iPhone 13']); const page=await ctx.newPage();
  await page.addInitScript(()=>{ window.__synced=1; window.__role='founder'; const d='2026-10-16T10:00:00Z';
    window.__staffRows=[
      {pseudo:'Zoe',answers:{q_inscription:'facile',q_inscription_pb:['mail'],g_snake:'oui',q_snake_speed:'trop_rapide',q_tactile_pb:['zoom','defile'],g_boybot:'oui',q_boybot:'bien'},comment:'Le serpent va trop vite au début.',completed_at:d,updated_at:d},
      {pseudo:'Bob',answers:{q_inscription:'echec',q_inscription_pb:['mail','mdp'],g_snake:'oui',q_snake_speed:'trop_rapide',q_tactile_pb:['zoom']},comment:'',completed_at:d,updated_at:d},
      {pseudo:'Lea',answers:{q_inscription:'tres_facile',g_snake:'non'},comment:'Hâte de voir la suite',completed_at:null,updated_at:d}]; });
  const errs=[]; page.on('pageerror',e=>errs.push(String(e.stack).slice(0,300)));
  await page.route('**/*', r=>{ const u=r.request().url();
    if(u.startsWith('http://x.test/')) { if(u==='http://x.test/'||u.startsWith('http://x.test/?')) return r.fulfill({contentType:'text/html',body:html});
      if(u.endsWith('config.js')) return r.fulfill({contentType:'text/javascript',body:'window.ARCADE_CONFIG={SUPABASE_URL:"https://x.supabase.co",SUPABASE_ANON_KEY:"k"};'});
      return r.fulfill({status:404,body:''}); }
    if(u.includes('supabase.js')) return r.fulfill({contentType:'text/javascript',body:fs.readFileSync(FT+'fake5.js','utf8')}); return r.fulfill({status:200,body:'',contentType:'text/css'}); });
  await page.goto('http://x.test/#admin'); await page.waitForTimeout(900);
  const link = await page.isVisible('text=RETOURS DU QUESTIONNAIRE'); await page.tap('text=RETOURS DU QUESTIONNAIRE'); await page.waitForTimeout(600);
  const kpis = await page.$$eval('.rt-kpi b', e=>e.map(x=>x.textContent));
  const top = await page.$$eval('.panel:has(h3:text("PROBLÈMES LES PLUS SIGNALÉS")) .rt-row .lab', e=>e.map(x=>x.textContent).slice(0,3));
  const coms = await page.$$eval('.rt-com p', e=>e.map(x=>x.textContent));
  await page.screenshot({path:FT+'captures/retours-iphone.png', fullPage:true});
  console.log('retours | lien admin :', link, '| envoyés/en cours/commentaires :', kpis.join('/'), '| top problèmes :', top.join(' ; '), '| commentaires :', coms.length);
  if (kpis.join('/') !== '2/1/2') fail('chiffres clés faux');
  if (!/E-mail de confirmation/.test(top[0])) fail('classement des problèmes inattendu');
  await page.tap('text=Compter seulement'); await page.waitForTimeout(300);
  const comsSent = await page.$$eval('.rt-com p', e=>e.length); if (comsSent !== 1) fail('filtre « envoyés » inopérant');
  if (errs.length) fail(errs.join('\n'));
  await b.close();
}
console.log('questionnaire OK');

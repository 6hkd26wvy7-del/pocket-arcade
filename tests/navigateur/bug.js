const { chromium } = require('playwright'); const fs=require('fs');
const ROOT=require('path').resolve(__dirname,'../..')+'/', FT=__dirname+'/'; require('fs').mkdirSync(FT+'captures',{recursive:true});
const html = fs.readFileSync(ROOT+'site/index.html','utf8');
async function run(b, fake, hash, fn){
 const ctx=await b.newContext({viewport:{width:390,height:800},hasTouch:true}); const page=await ctx.newPage();
 const errs=[]; page.on('pageerror',e=>errs.push(String(e))); page.on('dialog',d=>d.accept());
 await page.route('**/*', r=>{ const u=r.request().url();
  if(u.startsWith('http://x.test/')) { if(u==='http://x.test/'||u.startsWith('http://x.test/?')) return r.fulfill({contentType:'text/html',body:html}); if(u.endsWith('config.js')) return r.fulfill({contentType:'text/javascript',body:'window.ARCADE_CONFIG={SUPABASE_URL:"https://x.supabase.co",SUPABASE_ANON_KEY:"k"};'}); return r.fulfill({status:404,body:''}); }
  if(u.includes('supabase.js')) return r.fulfill({contentType:'text/javascript',body:fs.readFileSync(fake,'utf8')}); return r.fulfill({status:200,body:'',contentType:'text/css'}); });
 await page.goto('http://x.test/'+hash); await page.waitForTimeout(900);
 await fn(page); console.log('  erreurs JS:',JSON.stringify(errs)); await ctx.close();
}
(async()=>{
 const b=await chromium.launch();
 console.log('1) menu, envoi avec capture');
 await run(b,FT+'fake4.js','#menu',async page=>{
  console.log('  bouton visible:', await page.isVisible('#bug-fab'));
  await page.click('#bug-fab'); await page.waitForTimeout(200);
  await page.fill('#bug-card textarea','court'); await page.click('#bug-card button:has-text("ENVOYER")'); await page.waitForTimeout(200);
  console.log('  message court:', await page.innerText('#bug-card .msg'));
  await page.setInputFiles('#bug-card input[type=file]',FT+'shot.png'); await page.waitForTimeout(600);
  await page.fill('#bug-card textarea','Le bouton Jouer ne répond pas du tout sur mon téléphone.');
  await page.screenshot({path:FT+'captures/bug-form.png'});
  await page.click('#bug-card button:has-text("ENVOYER")'); await page.waitForTimeout(400);
  console.log('  après envoi:', await page.innerText('#bug-card .msg'));
  const a=await page.evaluate(()=>window.__bug); console.log('  envoyé:', a.p_category, '|', a.p_page, '|', a.p_app_version, '| capture jpeg:', (a.p_screenshot||'').startsWith('data:image/jpeg'), '| taille', (a.p_screenshot||'').length, '| device keys:', Object.keys(a.p_device).join(','));
  await page.waitForTimeout(2000); console.log('  fenêtre fermée:', await page.isHidden('#bug-modal'));
 });
 console.log('2) en jeu (Snake)');
 await run(b,FT+'fake4.js','#snake',async page=>{
  await page.keyboard.press('ArrowRight'); await page.keyboard.press('Space'); await page.waitForTimeout(600);
  const fab=await page.locator('#bug-fab').boundingBox(), ex=await page.locator('#g-exit').boundingBox();
  console.log('  FAB (x,y,w):', Math.round(fab.x),Math.round(fab.y),Math.round(fab.width),' sortie (x,y):',Math.round(ex.x),Math.round(ex.y));
  await page.screenshot({path:FT+'captures/bug-ingame.png'});
  await page.click('#bug-fab'); await page.waitForTimeout(200);
  await page.click('#bug-card textarea'); await page.keyboard.type('le jeu bloque ',{delay:20}); await page.keyboard.press('ArrowLeft'); await page.keyboard.type(' ok');
  console.log('  texte tapé (espaces conservés):', JSON.stringify(await page.inputValue('#bug-card textarea')));
  await page.screenshot({path:FT+'captures/bug-ingame-modal.png'});
  await page.keyboard.press('Escape'); await page.waitForTimeout(300);
  await page.screenshot({path:FT+'captures/bug-ingame-after.png'});
 });
 console.log('3) administration');
 await run(b,FT+'fake4.js','#admin',async page=>{
  const t=await page.innerText('#adm-body'); console.log('  panneau bugs:', /BUGS SIGNALÉS/.test(t), '| compteurs:', (t.match(/Nouveaux : \d+[^\n]*/)||[''])[0]);
  await page.click('.bugrow >> nth=0'); await page.waitForTimeout(200);
  await page.click('button:has-text("VOIR LA CAPTURE")'); await page.waitForTimeout(200);
  await page.selectOption('.bugdet select >> nth=0','in_progress'); await page.selectOption('.bugdet select >> nth=1','blocker');
  await page.click('button:has-text("ENREGISTRER")'); await page.waitForTimeout(300);
  console.log('  mise à jour envoyée:', JSON.stringify(await page.evaluate(()=>window.__upd)));
  await page.screenshot({path:FT+'captures/bug-admin.png',fullPage:true});
 });
 console.log('4) non connecté');
 await run(b,FT+'fake_out.js','#menu',async page=>{
  await page.click('#bug-fab'); console.log('  ', (await page.innerText('#bug-card')).replace(/\n/g,' | '));
 });
 await b.close();
})();

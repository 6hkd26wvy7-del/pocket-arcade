const { chromium } = require('playwright'); const fs=require('fs');
const html = fs.readFileSync('/tmp/stage-test/index.html','utf8');
(async()=>{
 const b=await chromium.launch(); const ctx=await b.newContext({viewport:{width:390,height:800},hasTouch:true}); const page=await ctx.newPage();
 const errs=[]; page.on('pageerror',e=>errs.push(String(e))); page.on('dialog',d=>d.accept());
 await page.route('**/*', r=>{ const u=r.request().url();
  if(u.startsWith('http://x.test/')) { if(u==='http://x.test/'||u.startsWith('http://x.test/?')) return r.fulfill({contentType:'text/html',body:html}); if(u.endsWith('config.js')) return r.fulfill({contentType:'text/javascript',body:'window.ARCADE_CONFIG={SUPABASE_URL:"https://x.supabase.co",SUPABASE_ANON_KEY:"k"};'}); return r.fulfill({status:404,body:''}); }
  if(u.includes('supabase.js')) return r.fulfill({contentType:'text/javascript',body:fs.readFileSync('/tmp/ft/fake3.js','utf8')}); return r.fulfill({status:200,body:'',contentType:'text/css'}); });
 await page.addInitScript(()=>{var rows=(n)=>Array.from({length:n},(_, i)=>({i}));var d={profiles:rows(3),messages:rows(5)};window.__EXP={format:'x',total_rows:8,integrity:{profiles:{rows:3},messages:{rows:5}},data:d};}); await page.goto('http://x.test/#admin'); await page.waitForTimeout(1000); await page.click('button:has-text("TÉLÉCHARGER LA SAUVEGARDE")'); await page.waitForTimeout(600); console.log('MSG:', (await page.innerText('body')).match(/Sauvegarde [^\n]*|Contrôle[^\n]*/g)); process.exit(0);
 await page.screenshot({path:'/tmp/ft/amis.png'});
 await page.click('#fr-list .who'); await page.waitForTimeout(400);
 const sheet=await page.innerText('#fr-profile'); console.log('FICHE:',sheet.replace(/\n/g,' | '));
 await page.screenshot({path:'/tmp/ft/fiche.png'});
 await page.click('#fr-profile button:has-text("MESSAGE")'); await page.waitForTimeout(400);
 const chat=await page.innerText('#fr-chat'); console.log('OFFRIR dans le chat ?', /OFFRIR/.test(chat));
 await page.click('#fr-list .who'); await page.waitForTimeout(300);
 await page.click('#fr-profile button:has-text("BLOQUER")'); await page.waitForTimeout(500);
 console.log('apres blocage:', (await page.innerText('#fr-list')).replace(/\n/g,' | '));
 await page.screenshot({path:'/tmp/ft/bloque.png'});
 await page.click('#fr-list button:has-text("DÉBLOQUER")'); await page.waitForTimeout(400);
 await page.goto('http://x.test/#compte'); await page.waitForTimeout(900);
 await page.click('.avgrid button:nth-child(7)'); await page.waitForTimeout(500);
 await page.click('.badge.pick:has-text("FONDATRICE")'); await page.waitForTimeout(500);
 const acc=await page.innerText('#acc-badges'); console.log('founder visible ?', /FONDATEUR/.test(acc), '| fondatrice visible ?', /FONDATRICE/.test(acc));
 await page.screenshot({path:'/tmp/ft/compte.png',fullPage:true});
 console.log(await page.evaluate(()=>window.__calls.filter(c=>/avatar|featured|block|public_profile/.test(c)).join('\n')));
 console.log('errors',JSON.stringify(errs)); await b.close();
})();

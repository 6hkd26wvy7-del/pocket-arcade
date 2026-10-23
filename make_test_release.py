#!/usr/bin/env python3
"""Prépare le site TEST dans test/ (version forcée sur boygam-test). Ne publie rien.
Usage : python3 -I make_test_release.py [nom-du-cache]"""
import os, re, shutil, subprocess, sys
ROOT = os.path.dirname(os.path.abspath(__file__)); OUT = os.path.join(ROOT, "test")
CACHE = sys.argv[1] if len(sys.argv) > 1 else "pocket-arcade-test-v10"
subprocess.check_call([sys.executable, "-I", os.path.join(ROOT, "build.py")], cwd=ROOT, stdout=subprocess.DEVNULL)
os.makedirs(OUT, exist_ok=True)
html = open(ROOT + "/site/index.html", encoding="utf-8").read()
a = "if (/[?&]env=test/.test(location.search)) {"; b = "var isTest = /[?&]env=test/.test(location.search);"
assert html.count(a) == 1 and html.count(b) == 1
html = html.replace(a, "if (true) {").replace(b, "var isTest = true;")
# numéro de version affiché dans les signalements de bug : date + empreinte du contenu (change à chaque modification)
import hashlib, datetime
stamp = datetime.date.today().strftime("%Y.%m.%d") + "-" + hashlib.md5(html.encode("utf-8")).hexdigest()[:6]
html, n = re.subn(r'var APP_BUILD = "[^"]*";', 'var APP_BUILD = "%s";' % stamp, html, count=1)
assert n == 1
open(OUT + "/index.html", "w", encoding="utf-8").write(html)
for n in ("config.test.js", "cgu.html", "privacy.html", "mentions-legales.html", "reglages-pub.js", "pub.js", "icon-180.png", "icon-192.png", "icon-512.png"):
    shutil.copyfile(ROOT + "/site/" + n, OUT + "/" + n)
# config.js du site TEST = réglages TEST aussi : même si config.test.js ne se charge pas, jamais la production.
shutil.copyfile(ROOT + "/site/config.test.js", OUT + "/config.js")
shutil.copyfile(ROOT + "/src/manifest.test.webmanifest", OUT + "/manifest.webmanifest")
sw = open(ROOT + "/site/sw.js", encoding="utf-8").read()
sw = re.sub(r'var CACHE = "[^"]+";', 'var CACHE = "%s";' % CACHE, sw, count=1)
open(OUT + "/sw.js", "w", encoding="utf-8").write(sw)
cfg = open(OUT + "/config.js", encoding="utf-8").read() + open(OUT + "/config.test.js", encoding="utf-8").read()
assert "xgoqwxvgiavajnygoblt" in cfg and "rvygnqpagbmiqbdkwlfp" not in cfg, "le site TEST ne doit pointer que vers boygam-test"
print("prêt :", OUT)

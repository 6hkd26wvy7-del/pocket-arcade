#!/usr/bin/env python3
"""Prépare /tmp/stage-release : site TEST forcé (test/) + serveur de duels (server/). Ne publie rien."""
import os, re, shutil, subprocess, sys
ROOT = os.path.dirname(os.path.abspath(__file__)); OUT = "/tmp/stage-release"; CACHE = sys.argv[1] if len(sys.argv) > 1 else "pocket-arcade-test-v9"
subprocess.check_call([sys.executable, "-I", os.path.join(ROOT, "build.py")], cwd=ROOT, stdout=subprocess.DEVNULL)
shutil.rmtree(OUT, ignore_errors=True); os.makedirs(OUT + "/test")
html = open(ROOT + "/site/index.html", encoding="utf-8").read()
a = "if (/[?&]env=test/.test(location.search)) {"; b = "var isTest = /[?&]env=test/.test(location.search);"
assert html.count(a) == 1 and html.count(b) == 1
html = html.replace(a, "if (true) {").replace(b, "var isTest = true;")
open(OUT + "/test/index.html", "w", encoding="utf-8").write(html)
for n in ("config.js", "config.test.js", "cgu.html", "privacy.html", "icon-180.png", "icon-192.png", "icon-512.png"):
    shutil.copyfile(ROOT + "/site/" + n, OUT + "/test/" + n)
shutil.copyfile("/tmp/stage-release-manifest.webmanifest" if os.path.exists("/tmp/stage-release-manifest.webmanifest") else ROOT + "/site/manifest.webmanifest", OUT + "/test/manifest.webmanifest")
sw = open(ROOT + "/site/sw.js", encoding="utf-8").read()
sw = re.sub(r'var CACHE = "[^"]+";', 'var CACHE = "%s";' % CACHE, sw, count=1)
open(OUT + "/test/sw.js", "w", encoding="utf-8").write(sw)
shutil.copytree(ROOT + "/server", OUT + "/server", ignore=shutil.ignore_patterns("node_modules"))
print("prêt :", OUT)

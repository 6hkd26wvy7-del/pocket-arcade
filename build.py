#!/usr/bin/env python3
"""Assemble the deployable site from the sources in src/.

Usage: python3 build.py
Output: site/index.html, site/config.js, site/privacy.html and pocket-arcade.zip
"""
import os
import shutil
import zipfile

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "src")
SITE = os.path.join(ROOT, "site")

with open(os.path.join(SRC, "app-fragment.html"), encoding="utf-8") as f:
    fragment = f.read()

import re
_eng = open(os.path.join(ROOT, "shared", "boyblocks-engine.js"), encoding="utf-8").read()
_names = re.findall(r"^export (?:const|function) (\w+)", _eng, re.M)
_eng = re.sub(r"^export ", "", _eng, flags=re.M)
_eng = "var BBE = (function () {\n" + _eng + "\nreturn {" + ", ".join(n + ": " + n for n in _names) + "};\n})();"
_bg = open(os.path.join(ROOT, "design", "badges", "badges.js"), encoding="utf-8").read()
assert "/*BG-BADGES*/" in fragment
fragment = fragment.replace("/*BG-BADGES*/", _bg)
assert "/*BOYBLOCKS-ENGINE*/" in fragment
fragment = fragment.replace("/*BOYBLOCKS-ENGINE*/", _eng)

head_part, body_part = fragment.split("<!--BODY-->", 1)

page = (
    "<!doctype html>\n"
    '<html lang="fr">\n'
    "<head>\n"
    '<meta charset="utf-8">\n'
    '<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">\n'
    + head_part.strip()
    + "\n</head>\n<body>\n"
    + body_part.strip()
    + "\n</body>\n</html>\n"
)

os.makedirs(SITE, exist_ok=True)
with open(os.path.join(SITE, "index.html"), "w", encoding="utf-8") as f:
    f.write(page)
SITE_FILES = (
    "index.html", "config.js", "config.test.js", "privacy.html", "cgu.html", "manifest.webmanifest", "sw.js",
    "icon-180.png", "icon-192.png", "icon-512.png",
)
for name in SITE_FILES[1:]:
    shutil.copyfile(os.path.join(SRC, name), os.path.join(SITE, name))

# Site files only, at the root of the zip: this is what gets uploaded to GitHub.
site_zip = os.path.join(ROOT, "pocket-arcade-site.zip")
with zipfile.ZipFile(site_zip, "w", zipfile.ZIP_DEFLATED) as z:
    for name in SITE_FILES:
        z.write(os.path.join(SITE, name), name)

zip_path = os.path.join(ROOT, "pocket-arcade.zip")
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as z:
    for name in SITE_FILES:
        z.write(os.path.join(SITE, name), "site/" + name)
    z.write(os.path.join(ROOT, "sql", "schema_all.sql"), "schema_all.sql")
    z.write(os.path.join(ROOT, "README.md"), "README.md")

print("built", SITE, "and", zip_path)

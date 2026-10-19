#!/bin/sh
# Prépare dist-preview/ (site TEST uniquement, jamais la production) pour Cloudflare Pages.
# Usage : sh cloudflare/preparer-previsualisation.sh   puis   npx wrangler pages deploy dist-preview --project-name boygames-preview --branch preview
set -e
cd "$(dirname "$0")/.."
python3 -I make_test_release.py >/dev/null
rm -rf dist-preview && mkdir dist-preview
cp test/* dist-preview/
cp cloudflare/_headers dist-preview/_headers
printf 'User-agent: *\nDisallow: /\n' > dist-preview/robots.txt
if grep -rq rvygnqpagbmiqbdkwlfp dist-preview; then echo "ERREUR : référence à la production"; exit 1; fi
grep -q xgoqwxvgiavajnygoblt dist-preview/config.js || { echo "ERREUR : config TEST absente"; exit 1; }
echo "OK : dist-preview prêt (config TEST uniquement)"

# BOYGAMES (pocket-arcade)

Pour reprendre le travail : lire `docs/JOURNAL.md`. Espace de travail sur le Mac : `~/Documents/BOYGAMES`.

| Dossier | Rôle |
|---|---|
| racine (`index.html`, `config.js`…) | site de **production** — ne pas modifier sans accord |
| `test/` | site **TEST** (base boygam-test), généré par `python3 make_test_release.py` — ne pas éditer à la main |
| `src/` | sources de l'application (`app-fragment.html`) ; `build.py` y insère `shared/` et `design/badges/` |
| `shared/boyblocks-engine.js` | moteur BoyBlocks, identique à `server/boyblocks-engine.js` et rejoué par la base (v8) |
| `server/` | serveur de duels Cloudflare (v4 : Snake, Block Drop, Space, BoyBlocks) |
| `sql/` | base Supabase : migrations à lancer, historique, tests — voir `sql/README.md` |
| `tests/navigateur/` | tests Playwright avec faux Supabase (Chromium + WebKit iPhone) |
| `marketing/` | machine marketing : vidéos 9:16 fabriquées à partir de vraies parties (`docs/MARKETING.md`) |
| `design/badges/` | ressources graphiques (emblèmes des paliers) |
| `docs/` | **`JOURNAL.md` (état et prochaines étapes)**, plan des phases, économie, monétisation, marketing, publication |
| `CLAUDE.md` | mémo technique pour les sessions de travail avec Claude |

## Tests

```
cd server && for f in test/*.test.mjs; do node $f; done                     # 66 tests du serveur
python3 sql/test/test_migrations.py && python3 sql/test/test_installation_et_moteur.py
cd tests/navigateur && npm install && npx playwright install chromium webkit && npm test
```

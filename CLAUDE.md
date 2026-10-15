# BOYGAMES — mémo pour les sessions de travail

Lire d'abord `docs/JOURNAL.md` (état et prochaines étapes), puis `docs/PLAN-PHASES.md`.

## Règles
- **Production intouchable sans accord explicite** : racine du site (`index.html`, `config.js`, `sw.js`, `privacy.html`,
  `manifest.webmanifest`, icônes) et base `rvygnqpagbmiqbdkwlfp`. Vérifier avant chaque publication que le diff
  `origin/main..HEAD` ne touche aucun de ces fichiers.
- TEST : site `test/` (généré, ne pas éditer à la main), base `boygam-test` = `xgoqwxvgiavajnygoblt`, serveur Cloudflare `boygam-arena`.
- Aucune donnée supprimée ; BC, scores, badges, messages préservés. Sauvegarde vérifiée (md5) avant chaque migration :
  `insert into sauvegardes.instantanes …` (schéma privé).
- Pas de publication publique (réseaux sociaux), de dépense ni de paiement sans accord.

## Où est quoi
| Besoin | Fichier |
|---|---|
| Application (une page) | `src/app-fragment.html` → `python3 -I make_test_release.py` génère `test/` |
| Moteur BoyBlocks (identique client/serveur/base) | `shared/boyblocks-engine.js` = `server/boyblocks-engine.js` = `bb_deal2`/`bb_replay2` en SQL |
| Space Attack (logique solo) | entre `/*SPACE-LOGIC-START*/` et `/*SPACE-LOGIC-END*/` dans `src/app-fragment.html` |
| Serveur de duels | `server/` (`npx wrangler deploy` depuis `server/`, PATH `~/.local/node/bin`) |
| Base | `sql/` : migrations `schema_v6_v7` → `v8_v9` → `v10` → `v11` → `v12` → `v13` → `v14` (BoyBlocks 9×9) ; installation neuve `schema_all.sql` |
| Fonctions autorisées au site | listes `api` / `anon_ok` de `sql/schema_v6_v7.sql` et `schema_all.sql` : y ajouter toute nouvelle fonction |
| Badges (visuels) | `design/badges/` |
| Marketing (vidéos) | `marketing/` ; workflow `.github/workflows/marketing-video.yml` (actif, quotidien) ; fonction Supabase `supabase/functions/marketing-ingest` (déployée via le connecteur, `verify_jwt` faux : elle vérifie elle-même le jeton) ; secret GitHub `MARKETING_INGEST_TOKEN` |

## Tests (tous doivent passer avant une publication)
```
cd server && for f in test/*.test.mjs; do node $f; done          # 68
node tests/logique/space.test.mjs                                 # 8
python3 sql/test/test_migrations.py                               # 110 (pip install pgserver psycopg2-binary)
python3 sql/test/test_installation_et_moteur.py                   # moteur JS = SQL sur 300 parties
python3 sql/test/test_execution_morcelee.py                       # pip install sqlparse
cd tests/navigateur && npm test                                   # 15 (Chromium + WebKit iPhone)
node tests/navigateur/en-ligne.mjs                                # site TEST publié
```
Node : `export PATH=~/.local/node/bin:$PATH`. Python des tests SQL : un venv avec `pgserver psycopg2-binary sqlparse`.

## Migration sur Supabase TEST
Exécuter le fichier entier d'un seul bloc (connecteur Supabase `execute_sql`), puis comparer l'empreinte des fonctions
(md5 de `prosrc`) avec celle obtenue sur la base locale de test. Les scripts s'arrêtent seuls s'ils sont exécutés en
plusieurs morceaux ou si une donnée existante change.

## État au 15/10/2026 (soir) — à reprendre
- **Base TEST : v14 appliquée** (9×9 en essai, réglage `game_settings.boyblocks9` activé ; données intactes vérifiées).
- **Site TEST publié = commit `4823f00` (8×8 seulement).** Le commit `925443a` (9×9 côté site) est sur la branche
  `recup/migrations-v6-v9`, **pas encore dans `main`**. La base v14 reste compatible avec ce site (8×8 inchangé).
- **Serveur de duels : v4 `4d9f8025` en ligne ; v5 (salles « Y » = duel 9×9) prête dans `server/`, pas déployée.**
- Pour finir l'essai 9×9 : `wrangler deploy` (v5), `make_test_release.py`, fast-forward `main`, `en-ligne.mjs`.
- Empreinte distante v14 : `81c4fbed…` (formule `md5(string_agg(proname||':'||md5(prosrc)))`) ; à recalculer en
  local avec la même formule (l'ancienne valeur `67358758…` utilisait une autre formule). Rejeu 9×9 distant = attendu.

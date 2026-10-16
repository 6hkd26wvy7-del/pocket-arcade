# BOYGAMES — mémo pour les sessions de travail

Lire d'abord `docs/JOURNAL.md` (état et prochaines étapes), puis `docs/AUDIT-2026-10-16.md` (état réel + feuille de route).

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
| BOYBOT (joueur virtuel) | `server/boybot.js` : cerveaux Snake / BoyBlocks / Space, niveaux easy/normal/hard ; branché dans `ArenaRoom` (`hello.bot`), place 2 |
| Serveur de duels | `server/` (`npx wrangler deploy` depuis `server/`, PATH `~/.local/node/bin`) |
| Base | `sql/` : migrations `schema_v6_v7` → `v8_v9` → `v10` → `v11` → `v12` → `v13` → `v14` (BoyBlocks 9×9) → `v15` (questionnaire bêta) → `v16` (espace bêta, missions, badge) → `v17` (plafond Space 100 000) ; installation neuve `schema_all.sql` |
| Fonctions autorisées au site | listes `api` / `anon_ok` de `sql/schema_v6_v7.sql` et `schema_all.sql` : y ajouter toute nouvelle fonction |
| Questionnaire bêta | liste `SURVEY` dans `src/app-fragment.html` (questions, options, « problèmes ») ; table `beta_survey` ; vues `#questionnaire` et `#retours` ; doc `docs/QUESTIONNAIRE.md` |
| Espace bêta / suivi | missions `BETA_MISSIONS` (textes) + `app_settings.beta_missions` (codes, obligatoires, manche) ; vues `#beta` (testeur) et `#suivi` (équipe : validation du badge `beta_tester`, CSV) ; badge attribué UNIQUEMENT par `staff_beta_validate` |
| Fiche profil | `openProfile(pseudo, {modal, record})` : depuis Amis ou en fenêtre depuis les classements ; défi = `arena.challenge(lettre)` + message |
| Badges (visuels) | `design/badges/` |
| Marketing (vidéos) | `marketing/` ; workflow `.github/workflows/marketing-video.yml` (actif, quotidien) ; fonction Supabase `supabase/functions/marketing-ingest` (déployée via le connecteur, `verify_jwt` faux : elle vérifie elle-même le jeton) ; secret GitHub `MARKETING_INGEST_TOKEN` |

## Tests (tous doivent passer avant une publication)
```
cd server && for f in test/*.test.mjs; do node $f; done          # 91
node tests/logique/space.test.mjs                                 # 8
python3 sql/test/test_migrations.py                               # 148 (pip install pgserver psycopg2-binary)
python3 sql/test/test_installation_et_moteur.py                   # moteur JS = SQL sur 300 parties
python3 sql/test/test_execution_morcelee.py                       # pip install sqlparse
cd tests/navigateur && npm test                                   # 20 (Chromium + WebKit iPhone)
node tests/navigateur/en-ligne.mjs                                # site TEST publié
```
Node : `export PATH=~/.local/node/bin:$PATH`. Python des tests SQL : un venv avec `pgserver psycopg2-binary sqlparse`.

## Migration sur Supabase TEST
Exécuter le fichier entier d'un seul bloc (connecteur Supabase `execute_sql`), puis comparer l'empreinte des fonctions
(md5 de `prosrc`) avec celle obtenue sur la base locale de test. Les scripts s'arrêtent seuls s'ils sont exécutés en
plusieurs morceaux ou si une donnée existante change.

## État au 16/10/2026 — à reprendre
- Base TEST v17 (plafond Space ; sauvegarde « avant v17 » id 8). v16 = espace bêta ( sauvegarde « avant v16 » id 7 vérifiée ; empreintes des fonctions v16 identiques au local). v15 = questionnaire. v14 = 9×9 en essai. Site TEST publié = `main` à jour. Serveur de duels v6 (BOYBOT).
  La production n'utilise pas le serveur de duels (pas d'`ARENA_URL` dans `config.js`).
- **BOYBOT** (bêta) : joueur virtuel côté serveur ; il envoie les mêmes ordres qu'un téléphone (mêmes validations).
  Signalé `bots:[false,true]` dans `lobby`/`countdown`. Pause (`pause`/`resume`, 3 s) uniquement dans les salles BOYBOT. Les duels ne donnent ni XP, ni BC, ni classement : si un jour
  ils en donnent, **exclure les salles où `bots` contient true**.
- Empreinte distante v14 : `81c4fbed…` (formule `md5(string_agg(proname||':'||md5(prosrc)))`) ; rejeu 9×9 distant = attendu.

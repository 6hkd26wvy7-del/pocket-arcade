# BOYGAMES — travail non publié (transfert du 15/10/2026)

Branche dédiée. Rien n'est publié, aucune migration Supabase lancée, aucun fichier existant du dépôt modifié :
tout est dans ce dossier `boygames-sources/` (fichiers exacts développés, sans réécriture).

## Contenu
- `src/app-fragment.html` : l'application complète (BoyBlocks solo + duel, avatars, profils d'amis, blocage, signalement de bug,
  badges à paliers + 3 favoris + animation, sauvegarde vérifiée admin, etc.). `build.py` l'assemble en `site/` ; il inline
  `shared/boyblocks-engine.js` et `design/badges/badges.js`.
- `shared/boyblocks-engine.js` : moteur BoyBlocks (identique à `server/boyblocks-engine.js`).
- `server/` : worker Cloudflare v4 (duel BoyBlocks, type de salle `X`, contrôle d'accès `arena_check`) + `boyblocks-duel.js`
  + `boyblocks-engine.js` + `test/` (8 fichiers, 66 tests).
- `schema_v6_v7_a_lancer.sql` (migration 1), `schema_v8_v9_a_lancer.sql` (migration 2, après la 1), `schema_v6a_sauvegarde.sql`,
  `schema_v*.sql` par version, `schema_all.sql` (installation neuve), `restore_backup.py`.
- `design/badges/` : générateur d'emblèmes (6 paliers) + planche de démonstration.
- `make_test_release.py` : prépare le site TEST forcé + serveur dans /tmp/stage-release (ne publie rien).
- `release-test-prepare/test/` : copie exacte du dossier `test/` préparé (index.html, sw.js cache test-v9…), pour comparaison.
- `tests-navigateur/` : scripts Playwright (bb.mjs solo, duel.mjs, tiers.mjs, regress.mjs, ui.js, bug.js…) et faux Supabase `fake*.js`.
  Chemins codés en dur (/tmp/ft, /home/claude/pocket-arcade, /opt/npm-tools) : à adapter.
- `tests-sql/` : stub Supabase, jeu de données `seed13.sql`, `schema_nov6.sql`, `gen.mjs` (comparaison moteur JS / rejeu SQL sur 300 parties), `pgup.sh`.

## Commandes
- Tests serveur : `cd server && for f in test/*.test.mjs; do node $f; done`
- Build : `python3 -I build.py` ; préparation TEST : `python3 -I make_test_release.py`

## Ordre d'application (à décider par Quentin, rien n'a été lancé)
1. SQL `schema_v6_v7_a_lancer.sql` sur boygam-test, puis `schema_v8_v9_a_lancer.sql`.
2. Publier `test/` (index.html, privacy.html, sw.js) puis le serveur (`server/`).
Le site fonctionne sans la migration 2 (BoyBlocks « hors classement », badges à paliers invisibles).

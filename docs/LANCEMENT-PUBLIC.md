# Lancement public BOYGAMES (23/10/2026)

Cette branche réunit les PR #6 (fins de partie), #5 (Space v25), #4 (invitations v24) et #7 (AdSense désactivé)
et régénère le site de **production** (racine) avec `python3 -I build.py`.

- Base visée : production `rvygnqpagbmiqbdkwlfp` (config.js inchangé).
- Duels en ligne : désactivés en production (pas d'`ARENA_URL` dans `config.js`, serveur `boygam-arena` sans accès BOYGAMES).
- Publicité : `reglages-pub.js` `enabled:false`, `approved:false` : aucun script Google, aucune bannière, aucun emplacement visible.
- Pages légales : `privacy.html`, `cgu.html`, `mentions-legales.html`.

## Ordre obligatoire (ne pas fusionner avant l'étape 2)
1. Réveiller le projet Supabase production (il est en pause : « INACTIVE »).
2. Lire la version réelle de la base production, faire la sauvegarde `sauvegardes.instantanes` (md5 vérifié), puis lancer
   dans l'ordre les migrations manquantes parmi `schema_v6_v7` → `v8_v9` → `v10` … `v23` → `v24` → `v25`,
   chacune d'un seul bloc, puis comparer les empreintes de fonctions avec la base locale de test.
3. Supabase production, Auth → URL Configuration : Site URL et Redirect URLs = `https://6hkd26wvy7-del.github.io/pocket-arcade/`.
4. Fusionner cette PR dans `main` : GitHub Pages publie la racine en 1 à 2 minutes.
5. Vérifier : ouverture du site, inscription/connexion, une partie Snake, score enregistré (table `scores`), classement.

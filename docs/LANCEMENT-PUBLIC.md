# Lancement public BOYGAMES (23/10/2026)

Cette branche réunit les PR #6 (fins de partie), #5 (Space v25), #4 (invitations v24) et #7 (AdSense désactivé)
et régénère le site de **production** (racine) avec `python3 -I build.py`.

- Base visée : production `rvygnqpagbmiqbdkwlfp` (config.js inchangé).
- Duels en ligne : désactivés en production (pas d'`ARENA_URL` dans `config.js`, serveur `boygam-arena` sans accès BOYGAMES).
- Publicité : `reglages-pub.js` `enabled:false`, `approved:false` : aucun script Google, aucune bannière, aucun emplacement visible.
- Pages légales : `privacy.html`, `cgu.html`, `mentions-legales.html`.

## Ordre obligatoire (ne pas fusionner avant l'étape 2)
1. Réveiller le projet Supabase production (il est en pause : « INACTIVE »).
2. Base production constatée le 23/10 : **v1** (2 tables `profiles` + `scores`, 5 profils, 99 scores Snake, aucune migration).
   Lancer **`sql/schema_prod_v1_v25.sql` en entier, d'un seul bloc** (SQL Editor). Il contient dans l'ordre v1→v4, v5, v6a, v6+v7,
   v8+v9, v10 … v25 dans une seule transaction, avec pré-contrôle (refuse toute autre base), sauvegarde md5 dans
   `sauvegardes.instantanes`, contrôle anti-perte final (profils et scores identiques) et bêta privée éteinte.
   Résultat attendu : `production v25 appliquée`, 5 profils, 99 scores, 49 tables publiques,
   `empreinte_fonctions = 02f9535276facf5dd4d8716943044064`. Essai local : `node sql/test/prod_v1_v25.test.mjs sql/schema_prod_v1_v25.sql`.
3. Supabase production, Auth → URL Configuration : Site URL et Redirect URLs = `https://6hkd26wvy7-del.github.io/pocket-arcade/`.
4. Fusionner cette PR dans `main` : GitHub Pages publie la racine en 1 à 2 minutes.
5. Vérifier : ouverture du site, inscription/connexion, une partie Snake, score enregistré (table `scores`), classement.

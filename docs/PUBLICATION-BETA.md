# Publier la bêta BOYGAMES sur le site TEST

Rien de ceci n'a été fait automatiquement. Chaque étape demande l'accord de Quentin.
La production (`index.html`, `config.js`… à la racine, base `rvygnqpagbmiqbdkwlfp`) n'est jamais touchée.

## Ordre obligatoire

1. **Migration 1** : coller `sql/schema_v6_v7.sql` dans Supabase > SQL Editor de **boygam-test** (`xgoqwxvgiavajnygoblt`), Run.
   Le résultat affiche « Migration appliquée ». En cas d'erreur, rien n'est modifié.
2. **Migration 2** : même chose avec `sql/schema_v8_v9.sql` (« Migration v8+v9 appliquée »).
3. **Serveur de duels** (Cloudflare) : `cd server && npx wrangler deploy`.
   Le serveur v4 appelle `arena_check` : **sans la migration 1, il refuse tous les duels**.
   Vérification : l'adresse du serveur affiche « BOYGAMES arena server v4 (duel BoyBlocks) ».
4. **Site TEST** : publier le dossier `test/` (déjà généré par `python3 make_test_release.py`) sur GitHub Pages.
   Sans la migration 1, les nouveaux écrans (avatars, blocage, bugs…) renvoient des erreurs.

Avant l'étape 1, télécharger une sauvegarde depuis l'administration du site (bouton « TÉLÉCHARGER LA SAUVEGARDE »).

## Vérifier sur iPhone (comptes tintintest et joh)

- Ouvrir https://6hkd26wvy7-del.github.io/pocket-arcade/test/ dans Safari, « Ajouter à l'écran d'accueil ».
- BoyBlocks solo : finir une partie → « Score vérifié et enregistré », le score apparaît au classement BoyBlocks.
- Duel BoyBlocks entre les deux comptes (salle « X »), puis « Rejouer ».
- Compte : changer d'avatar, choisir le badge affiché, 3 badges favoris.
- Amis : ouvrir la fiche de l'autre, bloquer puis débloquer.
- Bouton bug (en haut à droite) : envoyer un signalement avec capture ; le voir dans l'administration.

## Retour arrière

- Site : republier l'ancien `test/` (commit `b4c4230`).
- Serveur : `npx wrangler rollback`.
- Base : les migrations n'effacent aucune donnée. En dernier recours, `restore_backup.py` remet la sauvegarde téléchargée dans une base **vide** (schéma déjà créé).

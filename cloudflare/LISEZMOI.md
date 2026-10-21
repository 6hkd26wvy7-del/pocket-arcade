# Prévisualisation Cloudflare Pages (TEST uniquement)

Projet Pages distinct `boygames-preview` (adresse gratuite `*.pages.dev`), branche de test, jamais `main`.

1. `sh cloudflare/preparer-previsualisation.sh` : assemble `dist-preview/` depuis le site TEST (Supabase TEST seul, vérifié par le script).
2. `npx wrangler pages deploy dist-preview --project-name boygames-preview --branch preview` (envoi direct : pas de lien Git, donc aucun déploiement automatique de production).
3. Dans Cloudflare : Zero Trust > Access > Applications, protéger `boygames-preview.pages.dev` et `*.boygames-preview.pages.dev` (code envoyé par e-mail, gratuit jusqu'à 50 utilisateurs).
4. L'origine exacte `https://preview.boygames-preview.pages.dev` est déjà dans `server/wrangler.toml` (`ALLOWED_ORIGINS`, ancienne gardée) ; à ajouter aussi dans Supabase TEST > Auth > URL Configuration (Redirect URLs). Jamais la production.
5. Vérifier : chargement, connexion, une partie par jeu, duel, accès refusé sans authentification.

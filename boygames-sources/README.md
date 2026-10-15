# Pocket Arcade : mise en ligne

Ce dossier contient tout pour publier ton site de jeux avec comptes et classement.

- `site/` : le site à mettre en ligne (c'est ce dossier que tu déposes chez l'hébergeur)
- `schema.sql` : la base de données, à coller dans Supabase (ne se met pas en ligne)

## 1. Préparer Supabase (une seule fois)

1. Crée un projet sur supabase.com (région en Europe).
2. Ouvre **SQL Editor**, colle tout le contenu de `schema.sql`, clique **Run**. Tu dois voir « Success ».
3. Ouvre **Authentication**, puis **Sign In / Providers**, puis **Email**, et désactive **Confirm email**. Les joueurs se connectent avec une adresse e-mail et un mot de passe, sans e-mail de confirmation. Un mot de passe oublié ne peut pas être retrouvé.
4. Ouvre **Project Settings → API**. Copie le **Project URL** et la clé **anon public**.
5. Ouvre `site/config.js` et remplace les deux valeurs d'exemple par les tiennes.

## 2. Mettre le site en ligne

Le plus simple est de déposer le dossier `site/` sur Netlify (glisser-déposer) ou Cloudflare Pages. Tu obtiens une adresse web publique.

Ensuite, dans Supabase, **Authentication → URL Configuration** : mets l'adresse de ton site dans **Site URL**.

Un nom de domaine à toi (quelques euros par an) rend l'adresse plus sérieuse et plus facile à retenir. Il faudra le renouveler.

## 3. Points à régler avant d'ouvrir au public

- **E-mails** : le service d'e-mail intégré à Supabase est très limité en nombre d'envois. Pour un vrai lancement, branche un service d'e-mail à toi (Brevo, Resend, etc.) dans **Authentication → SMTP Settings**, sinon les codes n'arriveront pas à tout le monde.
- **Confidentialité** : ouvre `site/privacy.html` et remplace `[TON E-MAIL]` par une adresse de contact. Relis le texte et adapte-le si besoin.
- **Publicité** : si tu ajoutes des pubs, les régies demandent en général un bandeau de consentement aux cookies. Il faudra l'ajouter.
- **Sauvegardes** : exporte régulièrement ta base (Supabase propose des sauvegardes selon l'offre). Vérifie aussi si l'offre gratuite met en pause les projets peu actifs, et passe à une offre payante si le site grandit.

## Ajouter un jeu plus tard

1. Dans `schema.sql`, ajoute une ligne dans le `case` de `submit_score` avec le nom du jeu et son score maximum possible, puis relance le fichier dans Supabase.
2. Dans `site/index.html`, ajoute le jeu dans la liste `GAMES` et crée son écran.
3. Le compte et le classement fonctionnent déjà pour lui.

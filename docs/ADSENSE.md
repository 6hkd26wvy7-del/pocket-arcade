# Publicité Google AdSense : préparation (désactivée)

**État : code prêt, tout désactivé.** Aucune publicité, aucun script Google, aucun bandeau ne se charge tant que les
trois verrous ci-dessous ne sont pas ouverts. Aucun abonnement ni paiement : les jeux restent entièrement gratuits.

## Comment c'est construit

| Élément | Fichier |
|---|---|
| Réglages (identifiant éditeur, blocs d'annonces, interrupteurs) | `src/reglages-pub.js` |
| Décision, consentement, affichage | `src/pub.js` (appelé par `renderAds()` quand la régie choisie est `adsense`) |
| `ads.txt` | écrit par `build.py` dans `site/` **seulement** si `publisherId` est un vrai identifiant `ca-pub-` + 16 chiffres |
| Mentions légales | `src/mentions-legales.html` (champs `[à compléter]`) |
| Confidentialité, conditions | `src/privacy.html`, `src/cgu.html` (mis à jour : publicité, cookies, mineurs, droits, CNIL) |
| Tests | `tests/logique/pub.test.mjs` (8), `tests/navigateur/pub.mjs` (25 vérifications) |

**Trois verrous, tous nécessaires :**
1. `reglages-pub.js` : `enabled: true` **et** `approved: true` (à mettre seulement quand Google a approuvé le site)
   **et** un identifiant éditeur valide ;
2. Administration → Monétisation : « Activer les emplacements » + « Régie Google AdSense » + emplacements cochés ;
3. un identifiant de bloc d'annonces par emplacement dans `reglages-pub.js` (sinon cet emplacement reste vide).
Jamais d'annonce pour un joueur Premium (offre masquée, gardée par sécurité).

**Où :** accueil (sous les jeux), classements (en bas), boutique (en bas). Bandeau fixe de 100 px, marqué
« PUBLICITÉ ». **Jamais pendant une partie ou un duel** : les écrans de jeu n'ont aucun emplacement, et rien ne
s'affiche quand la page est en mode jeu (`body.ingame`). Les écrans de résultats sont dans les écrans de jeu : pas
de publicité non plus (choix volontaire, à rediscuter si besoin).

**Consentement :** l'outil de Google (AdSense → Confidentialité et messages → message RGPD), certifié IAB TCF v2.2,
exigé par Google pour l'Europe. Ordre de chargement : mode consentement v2 « tout refusé », puis bandeau de Google,
puis — seulement si l'utilisateur autorise le stockage (finalité 1) — le script d'annonces. Refus = aucune annonce.
Lien « GÉRER LES COOKIES » dans le pied de page pour changer d'avis.

**Mineurs :** toutes les annonces partent avec `data-tag-for-under-age-of-consent="1"` (TFUA) : pas de publicité
personnalisée ni de remarketing, pas de régies ou mesures tierces, pour tout le monde (on ne connaît pas l'âge des
joueurs). Coût : revenus plus faibles que des annonces personnalisées.

## Ce que Quentin devra fournir / faire (dans l'ordre)

1. **Un nom de domaine à soi** (ex. `boygames.fr`) : AdSense lit `ads.txt` à la racine du domaine, ce qui est
   impossible sous `6hkd26wvy7-del.github.io/pocket-arcade/`. À combiner avec la migration Cloudflare Pages.
2. Remplir les mentions légales (identité de l'éditeur, directeur de publication, hébergeur définitif).
3. Ajouter le site dans AdSense ; donner l'identifiant `ca-pub-…` → on le met dans `reglages-pub.js`
   (`enabled: true`, `approved: false`) : `ads.txt` est alors généré, sans aucune annonce.
4. Dans AdSense : créer le message RGPD (Confidentialité et messages), en français, avec « Ne pas consentir ».
   Dans « Contrôle du contenu » : bloquer les catégories sensibles (jeux d'argent, rencontres, alcool…), public jeune.
5. Après l'approbation Google : créer 2 ou 3 blocs d'annonces « display », donner leurs identifiants, passer
   `approved: true`, puis activer dans l'administration. **Mise en production uniquement sur accord.**

## Points de vigilance (mineurs, France)

- Majorité numérique en France : **15 ans** (loi Informatique et Libertés, art. 45). En dessous, le consentement aux
  cookies publicitaires doit être donné avec un parent. Le site ne connaît pas l'âge : d'où le TFUA pour tous et le
  rappel dans la confidentialité et les conditions. Option plus stricte possible : demander l'âge à l'inscription.
- Google interdit de cibler les moins de 13 ans de façon personnalisée ; si BOYGAMES vise explicitement les enfants,
  il faudrait le déclarer « destiné aux enfants » dans AdSense (TFCD) : encore moins de revenus.
- Les pages légales sont des brouillons rédigés pour être clairs ; une relecture par un professionnel est conseillée
  avant l'ouverture au public.

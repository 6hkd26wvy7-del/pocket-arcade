# BOYGAMES — étude : dons, publicités discrètes, bêta publique, identité visuelle (19/10/2026)

Rien n'est activé. Aucun service payant. Décisions à prendre par Quentin.

## 1. Dons volontaires (à la place de l'abonnement)

L'offre Premium à 0,99 €/mois est **masquée** sur TEST (signalement n°4) ; le réglage reste réactivable.

| Option | Coût | Mise en place | Remarques |
|---|---|---|---|
| **Lien externe de don** (Ko-fi, Buy Me a Coffee, Liberapay) | 0 € d'abonnement ; commission sur les dons (0 à 5 % selon le service + frais de paiement) | un bouton « Soutenir BOYGAMES » qui ouvre la page du service | le plus simple : aucun paiement dans l'appli, aucune donnée bancaire chez nous |
| Stripe Payment Link | frais par transaction seulement | lien + reçu automatique | compte Stripe et identité à créer par Quentin |
| Achat intégré iOS (application native) | 15 à 30 % Apple | seulement avec une appli App Store | inutile tant que BOYGAMES reste un site/PWA |

**Prêt (v23, désactivé)** : Administration → Monétisation → « Dons volontaires » (adresse Ko-fi, Liberapay, Buy Me a Coffee,
PayPal ou HelloAsso uniquement) ; une carte « Soutenir BOYGAMES » apparaît alors dans le Profil.

Recommandation : **bouton « Soutenir » vers une page Ko-fi ou Liberapay**, sans contrepartie en jeu (pas de BC, pas
d'avantage) ; éventuellement un badge cosmétique « Soutien » attribué manuellement par l'équipe. Mineurs : afficher
« demande l'accord d'un parent ».

## 2. Publicités discrètes

Déjà prêt (v12, mode test) : 3 emplacements hors partie (accueil, classements, boutique), jamais pendant une partie,
jamais pour un Premium, vidéo facultative pour continuer (score hors classement).

| Point | État / à faire avant activation |
|---|---|
| Régie | à choisir (ex. AdSense pour le web ; AdMob seulement en appli native) |
| Consentement RGPD | **obligatoire** avant toute pub personnalisée : bandeau CMP certifié (ex. Google Funding Choices, gratuit) |
| Public mineur | désactiver la personnalisation ; contenus « famille » |
| Politique de confidentialité | ajouter la régie et les cookies |

Recommandation : rester **sans publicité pendant la bêta** ; si besoin plus tard, une seule bannière sur l'accueil.

## 3. Bêta publique — prérequis

| Prérequis | État |
|---|---|
| Comptes : inscription, connexion, **mot de passe oublié** | fait le 19/10 (lien généré par l'équipe ; l'e-mail Supabase gratuit ne part qu'à l'équipe) |
| Envoi d'e-mails aux joueurs (confirmation, récupération autonome) | **à décider** : SMTP personnalisé (ex. Brevo/Resend, offre gratuite limitée) — compte à créer par Quentin |
| Invitations / bêta privée | fait (v18) ; pour une bêta publique : désactiver la bêta privée ou distribuer un lien multi-usage |
| Modération (signalements, suspension, filtre de mots, journal) | fait (v20) |
| Sécurité base (RLS, liste blanche, sauvegardes) | vérifiée le 16 et le 19/10 |
| Anti-triche scores Snake / Space / Block Drop solo | fait le 19/10 (v22) : ticket de partie + score vraisemblable pour la durée jouée |
| Matchmaking « trouver un adversaire » | à faire (repli BOYBOT) |
| Mentions légales, confidentialité, CGU, âge minimum | pages présentes ; à relire avant ouverture |
| Production | base de production à mettre au niveau v23 **sur accord explicite** |

## 4. Identité visuelle arcade premium

Planche « Cartouche néon » : `docs/design/identite-arcade.html` (+ captures PNG). À valider avant application.

Piste d'origine :

- Nom et logo : « BOYGAMES » en lettrage néon à deux couches (violet #7C3AED + cyan #22D3EE), contour pixel 1 px,
  légère lueur ; icône d'appli = manette pixel stylisée dans un cadre arrondi.
- Palette existante conservée (fond nuit #0F172A, cartes #1E293B) + un accent or pour les récompenses.
- Typographies : titres Rubik (déjà chargée), chiffres de score en police pixel ; pas de nouvelle dépendance payante.
- Ambiance : grille rétro discrète en fond d'accueil, cartes de jeu avec illustration propre à chaque jeu,
  écrans de fin unifiés (score, record, récompenses), sons courts cohérents.
- Livrables proposés : planche de style (couleurs, logo, boutons, cartes), icônes PWA, captures pour la bêta publique.

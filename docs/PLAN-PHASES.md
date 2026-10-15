# BOYGAMES — audit et plan d'exécution (octobre 2026)

Tout se fait sur TEST (site `test/`, base `boygam-test`, serveur `boygam-arena`). La production (racine du site,
base `rvygnqpagbmiqbdkwlfp`) n'est jamais touchée sans accord.

## Audit de départ (15/10)

| Domaine | Constat |
|---|---|
| Tactile iOS | protection seulement sur le canevas ; BoyBlocks absent de la règle CSS ; rien contre la sélection, la loupe et le zoom autour |
| Snake | nourriture = croix rouge ; pas de repère de cases |
| BoyBlocks | tirage au hasard (12 essais pour qu'une pièce rentre) ; même tirage rejoué dans la base (`bb_deal`) et utilisé en duel |
| Space Attack | vaisseau en 3 rectangles ; pas de bonus ; score déclaré par le téléphone (plafond 20 000 côté base) |
| Accueil | cartes en liste, une colonne ; navigation par onglets en haut |
| Économie | BC gagnés : parties (plafond 150 BC/jour), missions quotidiennes, connexion quotidienne, saison ; boutique : thèmes, skins, titres |
| Monétisation | rien (ni publicité, ni abonnement, ni paiement) |
| Marketing | rien ; pas de comptes sociaux |

## Phases

1. **Gameplay** — fait le 15/10 (voir ci-dessous).
2. **Accueil** — grille de 2 jeux par ligne, cartes compactes, barre de navigation fixe en bas (Accueil, Classements, Amis, Profil).
3. **Économie BC** — audit chiffré (gains possibles par jour et par semaine, prix), proposition d'équilibrage, réglages
   administrables. Aucun montant changé sans accord ; aucun BC retiré.
4. **Monétisation (préparation)** — emplacements publicitaires configurables hors partie, continuation par vidéo en solo
   (1 à 2 fois, partie marquée « continuée » et exclue des records/classements, ou classement séparé), Premium 0,99 €/mois
   (sans pub, badge Premium, cosmétiques, aucun avantage en jeu), badge à vie « Pionnier Premium ». Rien de réel.
5. **Machine marketing** — capture automatique de gameplay réel, montage 9:16, textes et légendes générés, file de
   publication dans le cloud avec validation humaine, tableau de bord. Coûts présentés avant tout service payant.
   Comptes TikTok / Instagram / YouTube à créer par Quentin (vérification d'identité, OAuth).
6. **Vérification générale** — tests mobiles complets et comptes rendus.

## Phase 1 — réalisé

- Tactile : pendant une partie, plus de sélection de texte, de loupe, de menu ni de zoom iOS ; les champs de saisie restent utilisables.
- Snake : pomme en pixel art avec feuille verte ; quadrillage discret.
- BoyBlocks : tirage « règles 2 » en solo (le meilleur de 4 lots selon les placements, lignes et combos possibles, 70 % du
  temps ; sinon au hasard). Duels inchangés. Chaque partie garde ses règles (migration v10). En simulation : parties
  moyennes de 85 coups au lieu de 47, aucune partie infinie.
- Space Attack : vaisseau pixel art (cockpit, ailes, réacteurs animés), bandeau sur deux lignes, 5 bonus à ramasser
  après chaque horde dès la vague 2 (triple tir 10 s, tir rapide 9 s, laser perçant 5 s, bouclier 15 s / 1 tir, vie +1 jusqu'à 5).

## Phase 2 — réalisé

- Accueil : les jeux d'abord, en cartes compactes et entièrement cliquables (illustration, titre, pastille de mode,
  phrase courte), 2 par ligne sur iPhone, 4 par ligne sur ordinateur ; carte « En ligne » en largeur.
- « Ta journée » ensuite : profil et XP, bonus de connexion, missions, saison, actualités, installation.
- Barre de navigation fixe en bas (téléphone) : Accueil, Classements, Amis, Profil. La boutique reste accessible par
  la pastille BOYCOINS de l'en-tête, qui affiche le solde. L'onglet actif suit chaque page (jeux → Accueil, boutique → Profil).
- Bandeau « version test » réduit à une fine pastille.

## Phase 3 — réalisé (proposition en attente de décision)

- Audit et proposition chiffrée : `docs/ECONOMIE-BOYCOINS.md`.
- Migration v11 appliquée sur TEST : réglages de l'économie administrables (valeurs d'origine, aucun montant modifié),
  panneau « Économie BOYCOINS » dans l'administration, bornes et journal des changements.

## Phase 3 — décision

- Proposition d'économie validée par Quentin et appliquée sur TEST (journalisée).

## Phase 4 — réalisé (préparation, rien de réel)

- Migration v12 appliquée sur TEST ; détails dans `docs/MONETISATION.md`.
- Publicités : 3 emplacements hors partie (accueil, classements, boutique), jamais pour un Premium.
- Continuation par vidéo (Snake, Space Attack) : score final hors classement ; vidéo de test de 5 s.
- Premium : badge, carte d'offre (bouton « bientôt disponible »), cosmétiques réservés, badge Pionnier à vie,
  simulation d'abonnement par l'équipe. Cadres de test activés sur TEST (désactivables dans l'administration).

## Phase 5 — conception faite (`docs/MARKETING.md`)

- Prototype : vidéo 9:16 en 1080x1920 fabriquée en moins d'une minute à partir d'une vraie partie (robot joueur, textes,
  musique générée, combos, écran de fin). Workflow cloud quotidien prêt, inactif tant qu'il n'est pas sur `main`.
- Devis ≈ 1 €/mois. Comptes à créer par Quentin : YouTube, Instagram pro + Page Facebook + Meta développeur, TikTok + développeur.
- TikTok : publications privées tant que l'application n'est pas auditée (règle officielle).

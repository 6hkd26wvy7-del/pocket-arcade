# Journal de suivi BOYGAMES

Le plus récent en haut. Chaque entrée : ce qui a été fait, où, et ce qui reste. Environnements : **TEST** = site
`…/pocket-arcade/test/` + base `boygam-test` (`xgoqwxvgiavajnygoblt`) + serveur `boygam-arena` ;
**PRODUCTION** = racine du site + base `rvygnqpagbmiqbdkwlfp` (jamais modifiée sans accord explicite).

---

## 19/10/2026 — reprise : comptes, mot de passe, signalements, sécurité (TEST)

- État vérifié : dépôt propre (dernier commit du 16/10), site TEST = `main`, base v20, serveur v6.
- Compte de Joh17 : sain en base (e-mail confirmé, bêta, non suspendu, dernière partie le 18/10, sessions renouvelées
  sans erreur). Le symptôme exact n'est pas dans les journaux disponibles (24 h). Manque réel trouvé : **aucune
  récupération de mot de passe** (le formulaire disait « si tu l'oublies, ton compte est perdu »).
  -> Fonction cloud `admin-reset-link` (TEST, droits vérifiés côté serveur, e-mail jamais renvoyé, journalisée) :
  Administration → Joueurs → fiche → LIEN MOT DE PASSE OUBLIÉ (1 h, usage unique) ; le joueur ouvre le lien, est
  connecté et choisit un nouveau mot de passe ; Profil → CHANGER MON MOT DE PASSE ; aide « mot de passe oublié ».
- Signalement n°3 (badge -> retour en haut de page) : position de la page conservée après un choix de badge / favori.
- Signalement n°4 (« enlever l'abonnement à 1 € ») : offre Premium masquée (réglage existant, journalisé) ; objets
  « réservés Premium » cachés en boutique tant que l'offre est masquée. Rien supprimé.
- Onglet Marketing : aperçus vidéo en erreur 400 depuis le verrouillage des fonctions (règle de stockage appelant
  `is_admin()`) -> migration v21 (rôle lu dans `user_roles`) : Fondateur 14 fichiers visibles, joueur 0.
- Contrôles : soldes BC = journal pour tous, aucun négatif, aucun score hors plafond ; les 2 journées > 40 BC datent
  d'avant le passage du plafond à 40 (15/10 14 h 21 UTC).
- Étude sans activation : `docs/ETUDE-SOUTIEN-BETA-PUBLIQUE.md` (dons, pubs, bêta publique, piste visuelle).
- Tests : SQL 175, moteur, morcelé, serveur 91, logique 8, navigateur 23 (`motdepasse.mjs`).

## 16/10/2026 — fiche administrative des joueurs (TEST)

- Administration → Joueurs : chaque ligne s'ouvre en fiche (profil, niveau/XP/BC, records, badges, bêta et missions,
  questionnaire, signalements reçus, bugs envoyés, historique). Actions regroupées, toutes confirmées et vérifiées
  côté serveur : bêta (ajouter/retirer), suspendre (durée + motif) / réactiver, rôle (Fondateur seulement), valider le
  badge BÊTA-TESTEUR si éligible, signalement traité. Rien pour modifier XP/BC/scores/badges ni supprimer un compte.
  RETOUR À LA LISTE garde recherche, filtre et page.
- Migration v20 (sauvegarde id 11) : `staff_player_detail` (lecture, sans e-mail ni messages) + journal `admin_actions`
  rempli par déclencheurs sur bans, beta_members, user_roles, beta_validations, reports, badges exclusifs (aucune
  fonction existante réécrite ; journal non modifiable par le site).
- Profils depuis les classements : revérifiés (test `beta-profils.mjs`).
- Tests : SQL 175 (+7), morcelé 10, navigateur 22 (`joueurs.mjs` étendu à la fiche).

## 16/10/2026 — « EL-MATHISSO introuvable » depuis le compte Fondateur (TEST)

- Vérifié en base TEST : compte présent, e-mail confirmé, membre de la bêta, un seul badge (ÉDITION FONDATRICE),
  0 partie. Le compte Fondateur utilise bien TEST (journaux : administration ouverte depuis l'iPhone à 13 h 22).
  `staff_beta_list` le renvoyait déjà.
- Causes : (1) l'administration n'avait AUCUNE liste des joueurs (seulement un compteur) ; (2) la liste bêta était
  une seule ligne de petit texte ; (3) les classements ne listent que les joueurs ayant un score (normal, il n'a pas joué).
- Correction : migration v19 `staff_players` (équipe, lecture seule, sans e-mail, sauvegarde id 10) + page
  Administration → VOIR TOUS LES JOUEURS (`#joueurs`) : tous les comptes même sans partie, recherche, filtres
  (bêta, hors bêta, sans partie, équipe, suspendus), pages de 20, ACTUALISER, AJOUTER À LA BÊTA ; liste bêta une
  ligne par membre avec la date d'ajout. Aucune donnée modifiée, aucun compte recréé, aucun badge ajouté.
- Tests : SQL 168, navigateur 22 (`joueurs.mjs`, iPhone).

## 16/10/2026 (nuit, suite) — invitations bêta par lien ou code (TEST)

- Administration → BÊTA PRIVÉE → INVITATIONS : créer un code (1 à 50 utilisations, 1 à 90 jours, note), lien
  `…/test/?invite=CODE`, COPIER / PARTAGER (iPhone), liste (usages, admis, expiration), ANNULER.
- Testeur : ouvre le lien -> le code est gardé sur l'appareil, retiré de l'adresse, et utilisé dès la connexion ou
  l'inscription (admis automatiquement) ; ou tape le code dans Profil si la bêta est privée et qu'il n'est pas admis.
- Base v18 (sauvegarde id 9) : `beta_invites`, `beta_invite_uses`, `beta_invite_fails` (10 essais ratés / heure),
  `beta_redeem`, `staff_beta_invite_create / invites / revoke`. Les règles existantes s'appliquent (badge
  ÉDITION FONDATRICE pour les 10 premiers membres, déclencheur inchangé).
- Tests : SQL 163 (+16), navigateur 21 (`invitations.mjs`, iPhone), essai réel sur TEST (annulé).

## 16/10/2026 (nuit) — audit global, corrections P1 (TEST)

- Audit complet code + base TEST + tests : `docs/AUDIT-2026-10-16.md` (25 domaines, états, feuille de route P1/P2/P3).
  Pas de cahier des charges consolidé du 15/10 dans le projet : références = demandes, PLAN-PHASES, HANDOFF, journal.
- Sécurité vérifiée en direct : RLS partout, fonctions joueur = liste blanche + staff_*, visiteurs = 5 lectures,
  aucune fuite (lignes personnelles seulement), 8 sauvegardes vérifiées.
- Bugs corrigés (signalements réels du 15/10) : plafond Space Attack 20 000 -> 100 000 (migration v17, sauvegarde id 8) ;
  message clair après une partie continuée (le score d'avant la vidéo est bien classé) ; numéro de version des
  signalements automatique (make_test_release).
- Tests : SQL 148 + moteur 300 parties + morcelé 8, serveur 91, logique 8, navigateur 20, site en ligne OK.
- Décisions : aucun gros chantier P2 commencé (validation requise) ; signalements n°1 et n°2 laissés « nouveau »
  pour vérification par Quentin sur iPhone.

## 16/10/2026 (soir) — défilement iPhone, profils depuis les classements, espace bêta, badge, suivi (TEST)

- Défilement iPhone : la page « Jouer en ligne » (section BOYBOT) avait `touch-action: none` en permanence ; la règle
  ne s'applique plus que pendant une partie (`body.ingame`). Protection anti-sélection conservée. Testé iPhone (PWA).
- Classements : appuyer sur un joueur ouvre sa fiche publique (fenêtre) : avatar, niveau, badge mis en avant, record
  du classement ; stats/badges détaillés pour les amis (règle de confidentialité existante) ; AJOUTER EN AMI ;
  DÉFIER (ami) = salle Snake ou BOYBLOCKS créée + code envoyé par message ; MESSAGE ; BLOQUER. Aucune donnée privée.
- Questionnaire : déjà terminé (23 questions validées) ; ajout d'un lien « signaler un bug » à la dernière étape.
- Espace bêta-testeur (`#beta`, Profil → ESPACE BÊTA-TESTEUR) : 11 missions, 4 statuts, note facultative, enregistrement
  automatique, progression en %, preuves déjà en base affichées (jamais validées automatiquement), bouton bug (capture
  facultative, outil existant), lien questionnaire. Manches : nouvelle manche possible après une mise à jour.
- Badge « BÊTA-TESTEUR BOYGAMES » (`beta_tester`, exclusif = permanent) : éligible si toutes les missions obligatoires
  sont remplies (réussi / problème / impossible) + questionnaire envoyé ; attribué seulement par un admin ;
  trouver un bug n'est pas nécessaire ; `beta_founder` et les autres badges intacts ; aucun badge attribué par la migration.
- Suivi bêta (`#suivi`, Administration → SUIVI BÊTA) : testeurs, avancement, missions (réussites / problèmes),
  questionnaire, bugs, preuves, décisions, VALIDER LE BADGE / À REVOIR, NOUVELLE MANCHE, EXPORT CSV ; liens vers
  Retours du questionnaire et bugs.
- Migration v16 sur TEST après sauvegarde vérifiée (id 7). Données intactes (5 profils, 70 scores, 14 badges, 457 BC).
- Tests : SQL 145, serveur 91, navigateur 20 (nouveau `beta-profils.mjs` sur iPhone). Serveur non redéployé (inchangé).
- À noter : la bêta privée est ACTIVÉE sur TEST ; un compte hors liste bêta ne peut ni jouer en ligne ni ouvrir
  l'espace bêta (Administration → bêta privée pour l'ajouter).
- EL-MATHISSO (compte créé le 16/10) ajouté à la liste bêta à la demande de Quentin (4 membres) ; il a reçu
  automatiquement le badge exclusif « BÊTA TESTEUR — ÉDITION FONDATRICE » (règle existante : 10 premiers, 4/10 attribués).

## 16/10/2026 (suite) — BOYBOT Snake corrigé + pause (retours de Joh)

- Constat mesuré : en Facile, BOYBOT réfléchissait un tour sur deux et un « bruit » aléatoire plus fort que l'attrait
  de la pomme le faisait tourner autour (1,4 pomme / 100 pas, 3 371 retours sur ses pas en 40 parties).
- État initial vérifié : positions en miroir, longueur 3, score 0, une case par tour comme l'humain ; aucun avantage.
- Nouveau déplacement : chemin le plus court (parcours en largeur) vers une pomme choisie et gardée, tout droit en
  priorité (pas de zigzag), mode survie quand aucune pomme n'est accessible (case qui laisse le plus de place).
  Niveaux = défauts humains : réflexes en retard, pomme moins bien choisie, pas d'anticipation des pièges (Facile) ;
  Difficile anticipe la tête adverse. Mesures : Facile 27 pommes / 2 min, Normal 67, Difficile 75 ;
  en duel, Facile gagne 25 % contre Normal, Normal 33 % contre Difficile.
- Pause contre BOYBOT (Snake, et aussi BoyBlocks / Space contre BOYBOT) : bouton PAUSE / REPRENDRE, compte à rebours
  3 s, plus aucun tour côté serveur pendant la pause (serpents, robot, temps de jeu figés), reprise au tour suivant,
  direction choisissable pendant le décompte, pause auto quand l'appli passe en arrière-plan.
  Refusée entre deux humains (règles des duels inchangées).
- Tests : 8 nouveaux tests serveur (91), test iPhone `boybot-pause.mjs` (19 navigateur). Serveur et site TEST déployés.

## 16/10/2026 — questionnaire des bêta-testeurs (TEST)

- Questionnaire intégré (`#questionnaire`) : une question par écran, gros boutons au doigt, barre de progression,
  23 questions en 9 parties (dont inscription/connexion, vitesse de Snake, BOYBOT), sections de jeu sautées si
  « Pas encore » testé, chaque question peut être passée, commentaire libre. Brouillon enregistré automatiquement
  (et envoyé tout de suite si l'appli passe en arrière-plan), réponses modifiables après envoi.
- Accès : rappel discret sur l'accueil tant que le questionnaire n'est pas envoyé ; bouton dans Profil.
- Administration → Retours bêta (`#retours`) : chiffres clés, problèmes les plus signalés (en nombre de testeurs),
  barres par question, commentaires, réponses par testeur ; filtre « envoyés seulement ».
- Base : migration v15 (`beta_survey`, `beta_survey_get/save`, `staff_beta_survey`) appliquée sur TEST après
  sauvegarde vérifiée (id 6) ; données intactes (4 profils, 70 scores, 457 BC). Moteurs, BOYBOT et serveur non touchés.
- La liste d'origine de 19 questions n'a pas été retrouvée : 23 questions reconstituées (voir `docs/QUESTIONNAIRE.md`),
  **validées par Quentin le 16/10/2026** (version 1 du questionnaire).

## 16/10/2026 — BOYBOT 🤖, joueur virtuel (TEST)

- Architecture : BOYBOT vit dans la salle de jeu du serveur (place 2). À chaque tour il envoie les mêmes ordres
  qu'un téléphone (direction, déplacement, pose), validés par les mêmes moteurs ; aucun jeu modifié.
- Snake : cherche les pommes, évite murs et corps, mesure l'espace libre (Normal/Difficile), évite le face-à-face (Difficile).
- BoyBlocks : évalue chaque pose (points, cases isolées, lignes presque pleines, pièces restantes posables), rythme humain.
- Space co-op : esquive les tirs, va chercher les bonus, vise l'ennemi le plus bas, visée imparfaite.
- Difficultés mesurées (moyennes) : Snake seul 5 / 47 / 67 pommes ; BoyBlocks 2 min 141 / 320 / 622 pts ;
  Space seul vague 3 / 3,3 / 4,3 (Facile / Normal / Difficile).
- Téléphone : section « JOUER AVEC BOYBOT 🤖 (BÊTA) » dans Jouer en ligne, difficulté mémorisée, « robot » affiché.
- Aucun impact récompenses : les duels n'attribuent ni XP, ni BC, ni classement ; drapeau `bots` pour l'avenir.
- Tests : 10 nouveaux tests serveur (83 au total), test navigateur `boybot.mjs` (Chromium + iPhone WebKit).
- À faire plus tard : ouvrir BOYBOT à tous (après la bêta), réglages fins de difficulté après essais réels.

## 15/10/2026 (soir, suite) — multijoueur harmonisé avec le solo (TEST)

- Snake 1V1 : quadrillage discret, pommes du solo, yeux dans le sens de la marche, glissé aussi sensible qu'en solo.
- Space Attack co-op : vaisseaux pixel art du solo (le tien bleu, coéquipier violet), flammes, étoiles, vies en cœurs.
- BoyBlocks 1V1 : déjà même moteur, dessin et aimant que le solo ; ajout de l'indication de combo.
- Règles et équité inchangées ; aucune donnée touchée. Serveur v5 déployé (`7b552562`), site TEST publié (`9688002`).
- Bonus Space Attack portés en co-op (accord de Quentin) : mêmes durées/fréquences/effets que le solo, le bonus va au
  vaisseau qui le ramasse ; serveur `e6ff47b1`, 73 tests serveur, 16 navigateur.

## 15/10/2026 (soir) — BoyBlocks 9×9 en essai (pause de session)

- Moteur BoyBlocks 8/9 (client, serveur, base), placement aimanté iPhone, classement `boyblocks9` séparé,
  bouton GRILLE 8×8 / 9×9, interrupteur d'administration pour revenir au 8×8. Tests : SQL 110, serveur 68, navigateur 15.
- **Fait sur TEST** : migration v14 (sauvegarde vérifiée avant) ; partie 9×9 rejouée à l'identique sur la base ;
  comptes (2), scores (28), parties BoyBlocks (7) intacts ; site TEST en ligne vérifié sans erreur.
- **Pas encore fait** : site 9×9 non publié (`main` reste à `4823f00`), serveur v5 (duel 9×9) non déployé.
- **À reprendre** : déployer serveur v5, publier le site, faire essayer le 9×9 ; phase 6 (vérification générale) ;
  comptes sociaux (Quentin).

## 15/10/2026 (fin d'après-midi) — marketing : fabrication activée, file de validation

- Migration v13 sur TEST (sauvegarde vérifiée avant) : `marketing_videos`, `marketing_posts`, `marketing_settings`,
  stockage privé `marketing`, jeton de dépôt (empreinte seule).
- Fonction Supabase `marketing-ingest` (TEST) : dépôt sécurisé ; testée (sans jeton → 403, doublon refusé).
- Workflow `.github/workflows/marketing-video.yml` actif sur `main` : 1 vidéo/jour vers 7 h, aucune publication.
- Onglet Administration → Marketing en ligne sur le site TEST.
- Espace de travail `~/Documents/BOYGAMES` créé (liens + copies, rien déplacé).
- Prochaines étapes : comptes sociaux (Quentin), puis publication YouTube/Instagram après validation humaine ;
  historique des accroches lu depuis la base (le cloud ne garde pas de mémoire entre deux passages).

## 15/10/2026 — reprise du projet et phases 1 à 5 (TEST)

**Reprise**
- Projet récupéré dans `~/Documents/GitHub/pocket-arcade`, branche de travail `recup/migrations-v6-v9`
  (poussée sur GitHub, fusionnée dans `main` pour publier le site TEST).
- Travail non publié de l'ancienne session intégré (81 fichiers : BoyBlocks solo/duel, paliers, profils, bugs, serveur v4).
- Erreur `_mig_before` comprise (ligne ajoutée par l'éditeur Supabase après le `commit`) et supprimée des migrations.

**Déployé sur TEST** (avec sauvegarde vérifiée avant chaque migration ; instantanés dans le schéma privé `sauvegardes`)
| Élément | Version |
|---|---|
| Base | v1 → v13 (v10 BoyBlocks règles 2, v11 réglages économie, v12 monétisation, v13 file marketing) |
| Serveur de duels | v4 corrigé (routeur des salles BoyBlocks « X »), version Cloudflare `4d9f8025` |
| Site TEST | `main` à jour (dernière publication : commit `ae6f32c`) |

**Phases du cahier des charges** (détails : `docs/PLAN-PHASES.md`)
1. Gameplay : tactile iOS, Snake (pomme, quadrillage), BoyBlocks tirage stratégique, Space Attack (vaisseau, bonus). ✅
2. Accueil : jeux 2 par ligne, barre de navigation à 4 onglets, pastille BOYCOINS. ✅
3. Économie : audit + proposition (`docs/ECONOMIE-BOYCOINS.md`), validée et appliquée sur TEST. ✅
4. Monétisation préparée (`docs/MONETISATION.md`) : pubs hors partie, continuation par vidéo, Premium simulé. ✅ (rien de réel)
5. Machine marketing (`docs/MARKETING.md`) : conception, devis ≈ 1 €/mois, comptes à créer, prototype de vidéos. ✅ conception
6. Vérification générale : à faire.

**Outils installés sur le Mac** (dans le dossier personnel, sans mot de passe)
Node.js `~/.local/node`, GitHub CLI `~/.local/bin/gh`, Wrangler + Supabase CLI `~/.local/boygames-tools`,
Playwright (Chromium, WebKit) dans `tests/navigateur` et `marketing`. Connexions autorisées : GitHub, Cloudflare,
Supabase (connecteur).

**Prochaines étapes**
- Quentin : tester sur iPhone les phases 1 à 4 ; créer les comptes YouTube / Instagram / TikTok (docs/MARKETING.md §4).
- Claude : file de validation + onglet Marketing (TEST), activation de la fabrication quotidienne (sur accord),
  publication YouTube puis Instagram (sur accord), phase 6.
- Décisions en attente : régie pub + consentement, prestataire de paiement, continuation BoyBlocks, BC des continuations.

# Questionnaire des bêta-testeurs (v1)

Validé par Quentin le 16/10/2026.

Source unique : la liste `SURVEY` dans `src/app-fragment.html` (bloc « Questionnaire des bêta-testeurs »). Pour changer une question,
modifier cette liste (identifiant court, texte, options) ; la base ne garde que les identifiants (`beta_survey`, migration v15).
Une option avec un 3e élément compte comme « problème » dans le classement de la page Administration → Retours bêta.
Chaque question peut être passée ; une section de jeu commence par « As-tu joué… ? » (« Pas encore » = section sautée).

## Inscription et accueil
1. **Créer ton compte et te connecter, c'était…** — `q_inscription`
   Très facile · Facile · Un peu compliqué ⚠ · Difficile ⚠ · Je n'ai pas réussi du premier coup ⚠
2. **As-tu eu un de ces soucis de compte ?** _(plusieurs choix)_ — `q_inscription_pb`
   E-mail de confirmation pas reçu ⚠ · Mot de passe refusé ⚠ · Pseudo refusé ⚠ · Déconnecté tout seul ⚠ · Aucun souci
3. **L'écran d'accueil te paraît…** — `q_accueil`
   Très clair · Clair · Un peu confus ⚠ · Vraiment confus ⚠
4. **Trouver les jeux, les classements et ton profil avec la barre du bas…** — `q_navigation`
   Facile · Ça va · Difficile ⚠

## Commandes sur téléphone
5. **Les commandes au doigt répondent…** — `q_tactile`
   Parfaitement · Bien · Parfois mal ⚠ · Mal ⚠
6. **En jouant, est-ce que…** _(plusieurs choix)_ — `q_tactile_pb`
   La page défile toute seule ⚠ · L'écran zoome sans le vouloir ⚠ · Un glissé n'est pas pris en compte ⚠ · Mon doigt cache le jeu ⚠ · Rien de tout ça

## Snake — question d’entrée : « As-tu joué à Snake ? »
7. **Snake, tu trouves ça…** — `q_snake_fun`
   Génial · Bien · Moyen · Pas terrible ⚠
8. **La vitesse du serpent est…** — `q_snake_speed`
   Trop lente ⚠ · Un peu lente · Parfaite · Un peu rapide · Trop rapide ⚠
9. **Dans Snake, as-tu remarqué…** _(plusieurs choix)_ — `q_snake_pb`
   Pomme difficile à voir ⚠ · Des virages ratés ⚠ · Une mort injuste ⚠ · Rien à signaler

## BOYBLOCKS — question d’entrée : « As-tu joué à BOYBLOCKS ? »
10. **BOYBLOCKS, tu trouves ça…** — `q_bb_fun`
   Génial · Bien · Moyen · Pas terrible ⚠
11. **Poser les pièces au doigt, c'est…** — `q_bb_place`
   Très facile · Facile · Imprécis ⚠ · Difficile ⚠
12. **Quelle grille préfères-tu ?** — `q_bb_grid`
   8 × 8 · 9 × 9 · Les deux me vont · Je n'ai pas essayé la 9 × 9

## Space Attack — question d’entrée : « As-tu joué à Space Attack ? »
13. **Space Attack, tu trouves ça…** — `q_space_fun`
   Génial · Bien · Moyen · Pas terrible ⚠
14. **Les bonus (tir triple, laser, bouclier…) sont…** — `q_space_bonus`
   Utiles et clairs · Utiles · Pas très clairs ⚠ · Je ne les ai pas remarqués ⚠
15. **La difficulté de Space Attack est…** — `q_space_diff`
   Trop facile ⚠ · Bien dosée · Trop difficile ⚠

## Jeux à deux en ligne — question d’entrée : « As-tu joué en ligne contre (ou avec) un ami ? »
16. **Les parties à deux, tu trouves ça…** — `q_duel_fun`
   Génial · Bien · Moyen · Pas terrible ⚠
17. **Pendant ces parties, as-tu eu…** _(plusieurs choix)_ — `q_duel_pb`
   Une connexion perdue ⚠ · Du décalage (lag) ⚠ · Un ami qui n'arrive pas à rejoindre ⚠ · Une partie qui ne démarre pas ⚠ · Aucun problème

## BOYBOT 🤖 — question d’entrée : « As-tu joué avec BOYBOT, le joueur virtuel ? »
18. **Comme adversaire ou coéquipier, BOYBOT est…** — `q_boybot`
   Trop facile ⚠ · Bien dosé · Trop fort ⚠ · Il joue bizarrement ⚠
19. **Il joue comme une vraie personne ?** — `q_boybot_human`
   Oui, c'est crédible · Plutôt · Pas vraiment ⚠

## Graphismes
20. **Les graphismes de BOYGAMES sont…** — `q_graphics`
   Superbes · Jolis · Corrects · À revoir ⚠
21. **As-tu remarqué…** _(plusieurs choix)_ — `q_graphics_pb`
   Du texte trop petit ⚠ · Des couleurs peu lisibles ⚠ · Des éléments coupés à l'écran ⚠ · Des lenteurs ⚠ · Rien de tout ça

## Récompenses
22. **XP, BOYCOINS et badges te donnent envie de rejouer ?** — `q_rewards`
   Beaucoup · Un peu · Pas vraiment ⚠ · Je ne les ai pas remarqués ⚠
23. **Recommanderais-tu BOYGAMES à un ami ?** — `q_reco`
   Oui, sûrement · Peut-être · Non ⚠

Plus un commentaire libre (2000 caractères au plus). ⚠ = réponse comptée comme problème signalé.

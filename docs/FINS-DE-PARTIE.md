# Fins de partie — état et points d'accroche (20/10/2026)

## Snake : grille pleine = victoire
- Grille 18 × 24 = 432 cases, serpent de départ 3 : score maximal **429** (= limite serveur de Snake, vraisemblance : 111 s minimum).
- Logique pure testable : `SNK` entre `/*SNAKE-LOGIC-START*/` et `/*SNAKE-LOGIC-END*/` ; test : `node tests/logique/snake.test.mjs`.
- Nourriture : un seul passage sur les cases libres, `null` quand il n'en reste aucune (aucune boucle d'essais au hasard, aucun blocage).
- `win()` : état `won`, fanfare, écran « VICTOIRE ! GRILLE COMPLETE », message et boutons REJOUER / ACCUEIL (`#snake-win`).
  `finish()` ne s'exécute qu'une fois (pas de double envoi). Le score part par le chemin normal (ticket + `submit_score_v2`).
- Parties continuées par vidéo : la victoire ne propose pas de continuation ; le score reste hors classement.

## Points d'accroche (sans effet aujourd'hui, aucune récompense réelle modifiée)
- Animation du héros : élément `#snake-hero` (masqué) affiché à la victoire ; à habiller avec le nouveau design.
- Événement `document` « boygames:victory » `{ game, score, perfect, ranked }` : le futur écran de victoire, le son et l'animation s'y abonnent.
- Badge « grille complète » : à créer côté base (nouveau badge + condition dans `check_badges`, score snake = 429 sur une partie classée),
  jamais côté site. Migration à préparer en fichier puis à valider par le propriétaire.

## Autres jeux (constats, rien de bloquant)
- Block Drop : la fin = pièce qui ne rentre plus ; `finish()` protégé contre la double fin.
- Space Attack : vagues sans fin ; le Game Over est la seule fin. Garde de double fin à ajouter avec #5 (même zone de code).
- BoyBlocks : fin « plus aucun coup » décidée par le moteur et rejouée côté base.

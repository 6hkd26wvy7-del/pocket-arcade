# PULSE — prototype de mini-jeu (essai)

Jeu à un doigt : un noyau au centre, des orbes arrivent des bords. Un tap lance une onde qui détruit tout ce qu'elle traverse
(3 charges d'énergie, recharge continue). Cyan = 1 onde, violet = 2 ondes, corail (bombe) = à ne pas toucher.
Plusieurs orbes dans la même onde = combo. 3 vies.

- **Essayer** : ouvrir `prototypes/pulse/index.html` (iPhone : l'héberger sur un aperçu, ou `python3 -m http.server` depuis ce dossier).
- **Tests** : `node prototypes/pulse/pulse.test.mjs` (13 tests, logique pure et déterministe par graine).
- **Isolé** : aucun appel réseau, aucun score envoyé, ni BOYCOINS ni XP, rien dans `src/`, `test/`, `server/` ni `sql/`.
- Palette de `docs/` « Cartouche néon » (Nuit, Signal, Volt, Corail, Mandarine) ; formes simples, sans mascotte.
- Pour l'intégrer plus tard : `pulse-logic.js` est autonome (modèle de `server/space-engine.js` si un rejeu serveur est voulu).

# Serveur de jeu BOYGAMES (Snake Arena)

Fonctionne sur Cloudflare Workers (offre gratuite). Aucun secret dans ce dossier.

- `arena-engine.js` : les règles du jeu (testées : `node test/engine.test.mjs`).
- `worker.js` : les salles à 2 joueurs, la vérification de connexion, la déconnexion (`node test/room.test.mjs`).
- `../wrangler.toml` (à la racine du dépôt) : réglages Cloudflare (adresse Supabase publique, sites autorisés).

Mise en ligne (une seule fois) : voir les explications données dans la conversation avec Claude.
Ensuite, mettre l'adresse du serveur dans `config.js` / `config.test.js` : `ARENA_URL: "wss://…workers.dev"`.

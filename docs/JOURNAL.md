# Journal de suivi BOYGAMES

Le plus récent en haut. Chaque entrée : ce qui a été fait, où, et ce qui reste. Environnements : **TEST** = site
`…/pocket-arcade/test/` + base `boygam-test` (`xgoqwxvgiavajnygoblt`) + serveur `boygam-arena` ;
**PRODUCTION** = racine du site + base `rvygnqpagbmiqbdkwlfp` (jamais modifiée sans accord explicite).

---

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

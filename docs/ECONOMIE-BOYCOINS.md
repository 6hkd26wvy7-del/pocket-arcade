# Économie BOYCOINS : audit et proposition (phase 3)

**Statut (15/10) : proposition validée par Quentin et appliquée sur TEST (journalisée dans economy_log).** Les réglages administrables (migration v11) reprennent les
montants actuels à l'identique. Aucun BC déjà gagné n'est retiré, aucun objet acheté n'est repris.

## 1. Audit : d'où viennent les BC aujourd'hui

| Source | Règle actuelle | Maximum |
|---|---|---|
| Parties | 1 + score ÷ diviseur (Snake ÷10 sans plafond, Block Drop ÷200, Space ÷100, BoyBlocks ÷400, plafonnés à 26 par partie) | **150 BC / jour** (tous jeux confondus) |
| Missions quotidiennes | Joue 3 parties 20 · Snake 20 pts 25 · Joue 10 parties 50 · BoyBlocks 1 500 pts 30 | **125 BC / jour** |
| Connexion quotidienne | J1 à J7 : 10, 15, 20, 25, 30, 40, 100 | **240 BC / semaine** |
| Saison (par jeu, chaque mois) | 1er 500 · 2e-3e 300 · 4e-10e 150 · autres classés 30 | jusqu'à **2 000 BC / mois** pour un joueur 1er partout |
| Badges, niveaux | aucun BC | — |
| Cadeaux entre joueurs | supprimés (v6) | — |

Boutique actuelle (100 % cosmétique, aucun avantage en jeu) : Titre Recrue 50 · Thème Nuit 100 · Thème Coucher de
soleil 150 · Serpent Néon 200 · Serpent Doré 400 · Titre Légende 500. **Total : 1 400 BC.**

Données réelles TEST (2 testeurs, 2 jours) : 313 BC gagnés, dont 138 en parties, 140 en missions, 35 en connexion.
Scores moyens : Snake 13, Block Drop 2 503, Space Attack 3 703, BoyBlocks 439.

**Constats**
1. **Trop généreux** : un joueur régulier (20 min/jour) gagne ~930 BC/semaine et peut tout acheter en 10 jours.
2. **Déséquilibré entre jeux** : une partie moyenne de Space Attack rapporte 26 BC (le maximum), Snake ou BoyBlocks 2.
3. **Le plafond de 150 BC/jour est atteint en 6 parties de Space Attack.**
4. Les missions rapportent autant que les parties : bien pour la fidélité, mais trop haut en valeur absolue.

## 2. Simulation par profil (scores moyens réels)

| Profil | Actuel / semaine | Proposé / semaine | Titre Légende (500) actuel → proposé |
|---|---|---|---|
| Occasionnel (5 min, 3 parties, 3 j/sem) | 228 BC | 77 BC | 15 j → 46 j |
| Régulier (20 min, 8 parties, 6 j/sem) | 926 BC | 324 BC | 4 j → 11 j |
| Assidu (1 h, 25 parties, 7 j/sem) | 2 165 BC | 695 BC | 2 j → 5 j |

## 3. Proposition

Repère de valeur pour une future vente de BC (à décider plus tard) : **100 BC ≈ 1 €** (par exemple 500 BC à 4,99 €,
1 200 BC à 9,99 €). Objectif : un joueur régulier gratuit obtient un cosmétique moyen toutes les 1 à 2 semaines et
un objet rare en ~1 mois. Rien ne s'achète qui donne un avantage en jeu.

| Réglage | Actuel | Proposé |
|---|---|---|
| Gain par partie | 1 + score ÷ (10 / 200 / 100 / 400), max 26 | 1 + score ÷ (Snake 10, Block Drop 1 000, Space 1 000, BoyBlocks 300), **max 5** |
| Plafond parties / jour | 150 | **40** |
| Missions (Joue 3 / Snake 20 / Joue 10 / BoyBlocks 1 500) | 20 / 25 / 50 / 30 | **10 / 10 / 15 / 10** |
| Connexion J1→J7 | 10-15-20-25-30-40-100 (240/sem) | **5-5-10-10-15-15-40 (100/sem)** |
| Saison par jeu (1er / 2-3 / 4-10 / autres) | 500 / 300 / 150 / 30 | **200 / 120 / 60 / 10** |

Prix de la boutique proposés (les objets déjà achetés restent acquis) :

| Objet | Actuel | Proposé | Joueur régulier |
|---|---|---|---|
| Titre : Recrue | 50 | 100 | 2 jours |
| Thème Nuit | 100 | 300 | 1 semaine |
| Thème Coucher de soleil | 150 | 300 | 1 semaine |
| Serpent Néon | 200 | 500 | 1,5 semaine |
| Serpent Doré | 400 | 900 | 3 semaines |
| Titre : Légende | 500 | 1 500 | 4,5 semaines |

Pistes complémentaires (à valider séparément) : missions hebdomadaires (ex. « 30 parties dans la semaine » 60 BC),
gain par partie basé sur le temps de jeu plutôt que le score (plus juste entre jeux), et objets Premium exclusifs
non achetables en BC.

## 4. Réglages administrables (migration v11, prête)

Dans l'administration du site (fondateur / admin) : panneau **ÉCONOMIE BOYCOINS**.
- Gains par partie (diviseur et plafond par jeu), plafond quotidien, bonus de connexion, récompenses de saison.
- Prix de chaque objet de la boutique, récompenses BC/XP de chaque mission.
- Chaque modification demande une confirmation, est **bornée** côté base (impossible de distribuer 99 999 BC par
  erreur) et **journalisée** (qui, quand, avant, après).

Appliquer la proposition ci-dessus = quelques modifications dans ce panneau, après accord.

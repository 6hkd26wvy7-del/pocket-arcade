# Base de données BOYGAMES (Supabase)

## Ce qui reste à lancer sur boygam-test (dans Supabase > SQL Editor, dans cet ordre)

1. `schema_v6_v7.sql` : avatars, badge affiché, blocage, fiches d'amis, badges exclusifs, fin des cadeaux de BC,
   signalement de bugs, **liste blanche des droits**, `arena_check` pour le serveur de duels.
2. `schema_v8_v9.sql` : BoyBlocks vérifié côté base (la base rejoue la partie), badges à paliers, favoris.

Chaque script est tout-ou-rien, relançable, et s'annule tout seul si des données existantes changent.

## Fichiers

| Fichier | Rôle |
|---|---|
| `schema_all.sql` | installation **neuve** complète (v1 à v9), pour un nouveau projet Supabase |
| `schema_v6_v7.sql`, `schema_v8_v9.sql` | les deux migrations à lancer sur une base existante |
| `historique/` | chaque version séparée, telle qu'elle a été écrite. Déjà appliquées sur boygam-test : v1 à v5 et `schema_v6a_sauvegarde.sql` |
| `test/` | essais sur une base PostgreSQL locale jetable (jamais Supabase) |

## Règle des droits (depuis la v7)

Aucune fonction n'est appelable par le site, sauf celles des deux listes `api` de `schema_v6_v7.sql`
(plus les fonctions `staff_*`, qui vérifient elles-mêmes le rôle admin). Une nouvelle fonction appelée
par le site doit recevoir un `grant execute ... to authenticated` explicite **et** être ajoutée à ces listes
(et à celle de `schema_all.sql`), sinon une relance de la v6+v7 la coupera.

## Essayer sans toucher à Supabase

```
pip install pgserver psycopg2-binary
python3 sql/test/test_migrations.py              # chemin réel de boygam-test : v1-v5, v6a, puis les 2 migrations (52 vérifications)
python3 sql/test/test_installation_et_moteur.py  # installation neuve + moteur JS = rejeu SQL sur 300 parties (Node requis)
python3 sql/test/test_execution_morcelee.py      # exécution en plusieurs morceaux : arrêt avant toute modification (pip install sqlparse)
```

# Base de données BOYGAMES (Supabase)

À lancer **sur boygam-test d'abord**, dans Supabase > SQL Editor, dans cet ordre :

| Fichier | Contenu | État sur boygam-test (15/10) |
|---|---|---|
| `schema_all.sql` | v1 à v4 : profils, scores, XP, BOYCOINS, badges, missions, amis, messages, saison… | appliqué |
| `schema_v5.sql` | récompenses de saison, bêta privée, rôles, sauvegarde | appliqué |
| `schema_v6a_sauvegarde.sql` | sauvegarde complète (19 tables) + contrôle d'intégrité | appliqué (la sauvegarde du 15/10 est au format v2) |
| `schema_v6_v7.sql` | avatars, badge affiché, blocage, fiches d'amis, badges exclusifs, fin des cadeaux de BC, signalement de bugs, **liste blanche des droits** | **pas encore lancé** |
| `schema_v8_v9.sql` | BoyBlocks vérifié côté base (la base rejoue la partie), badges à paliers, favoris | **pas encore lancé** |

Chaque script est tout-ou-rien, relançable, et s'annule tout seul si des données existantes changent.

## Règle des droits (depuis la v7)

Aucune fonction n'est appelable par le site, sauf celles des deux listes `api` de `schema_v6_v7.sql`
(plus les fonctions `staff_*`, qui vérifient elles-mêmes le rôle admin). Une nouvelle fonction appelée
par le site doit recevoir un `grant execute ... to authenticated` explicite **et** être ajoutée à ces listes,
sinon une relance de la v6+v7 la coupera.

## Essayer les migrations sans toucher à Supabase

```
pip install pgserver psycopg2-binary
python3 sql/test/test_migrations.py
```

Le script crée une base PostgreSQL jetable qui imite Supabase (rôles `anon` / `authenticated`, `auth.uid()`),
applique tous les fichiers, puis vérifie les fonctions et les droits joueur par joueur.

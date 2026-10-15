# Machine marketing BOYGAMES (phase 5)

**État au 15/10/2026 : conception + prototype de fabrication fonctionnel. Rien n'est publié, aucun compte créé,
aucune dépense.** Le prototype fabrique en moins d'une minute une vidéo 9:16 à partir d'une vraie partie.

## 1. Architecture (fonctionne Mac éteint)

```
GitHub Actions (cloud, chaque jour)                       Supabase (base)                Site (administration)
 ├─ 1. choisit une belle partie (simulation du vrai moteur)   marketing_videos :            onglet « Marketing » :
 ├─ 2. la filme sur le vrai site (navigateur, 1080x1920)       statut, textes, fichier,      aperçu, valider/refuser,
 ├─ 3. écrit accroche/légende/hashtags (Claude)                plateformes, erreurs,         calendrier, mode auto,
 ├─ 4. monte : textes, combos, musique générée, fin            identifiants de publication   erreurs, statistiques
 └─ 5. dépose la vidéo (stockage) + ligne « à valider »  ───────────────►
GitHub Actions (cloud, toutes les heures)
 └─ publie les vidéos VALIDÉES et arrivées à échéance : YouTube Shorts, Instagram Reels, TikTok
    (une ligne par vidéo et par plateforme ; jamais republiée si déjà « publiée » ; 3 essais espacés puis « erreur »)
```

| Brique | Choix | Pourquoi |
|---|---|---|
| Exécution | GitHub Actions (`.github/workflows/marketing-video.yml`) | gratuit pour un dépôt public, déjà connecté, tourne sans le Mac |
| Contenu | vraies parties du vrai site, jouées par un robot | authentique, varié (chaque graine = une partie différente), aucun droit à payer |
| Textes | Claude Opus 5.5 avec les vrais chiffres de la partie + historique anti-répétition | quelques centimes par mois ; modèles de secours sans clé |
| Musique | chiptune générée par le code (gamme, tempo, motif varient) | aucun risque de droits ni de blocage « Content ID » |
| Montage | ffmpeg (accroche 3 s, « COMBO » aux vrais moments, écran de fin) | gratuit, rapide |
| Stockage vidéos | Cloudflare R2 (10 Go gratuits, sans frais de sortie) | Instagram exige une adresse publique de la vidéo |
| File + historique | table Supabase `marketing_videos` + `marketing_posts` | statuts, reprises contrôlées, pas de doublon |
| Suivi du trafic | liens avec `?utm_source=tiktok…` + table `acquisition` (visites, inscriptions) | mesurer l'effet réel des vidéos |

### Variété (éviter les vidéos répétitives)
Jeux différents selon les jours (BoyBlocks prêt ; Snake, Space Attack, duels à brancher), formats tournants
(« record », « combo », « défi : fais mieux », « nouveauté », « avant/après bonus »), accroches jamais réutilisées
(historique), musiques toutes différentes, durées de 15 à 30 s.

### Validation puis autonomie
1. **Mode validation (au départ)** : chaque vidéo arrive « à valider » ; rien ne part sans ton clic.
2. **Mode automatique (plus tard, activable dans l'administration)** : les vidéos sont publiées seules à l'heure
   prévue, avec un garde-fou (limite 1 par jour et par plateforme, arrêt automatique après 3 erreurs de suite).

## 2. Ce que permettent vraiment les plateformes (vérifié le 15/10/2026)

| Plateforme | Publication par API | Limite importante |
|---|---|---|
| **YouTube Shorts** | API YouTube Data v3 (`videos.insert`) | 100 envois/jour. La documentation officielle indique que les vidéos d'un projet non vérifié **ne sont pas** limitées au mode privé. |
| **Instagram Reels** | API Instagram (compte **professionnel**) : conteneur `REELS` puis `media_publish` | quota de publications par 24 h (consultable via `content_publishing_limit`) ; la vidéo doit être à une adresse publique. Pour publier sur **notre propre compte**, l'application peut rester en mode développement (pas de revue Meta). |
| **TikTok** | Content Posting API (« Direct Post », droit `video.publish`) | **tant que TikTok n'a pas audité l'application, toutes les publications sont privées.** L'audit demande une politique de confidentialité, des conditions d'utilisation et une vidéo de démonstration. Plafond quotidien par compte non chiffré dans la doc. |

En attendant l'audit TikTok : la vidéo et sa légende sont prêtes chaque jour dans l'administration, et tu la postes
toi-même depuis l'application TikTok (1 minute). Aucun contournement (pas de robot de connexion, pas d'automatisation
de l'application).

Sources : [YouTube videos.insert](https://developers.google.com/youtube/v3/docs/videos/insert) ·
[TikTok Direct Post](https://developers.tiktok.com/doc/content-posting-api-reference-direct-post) ·
[Guide Instagram Reels API 2026 (tiers)](https://postproxy.dev/blog/instagram-reels-api-publishing-guide/) — les
détails Instagram viennent de guides tiers et seront revérifiés dans la documentation Meta au moment du branchement.

## 3. Devis mensuel

| Poste | Coût / mois |
|---|---|
| GitHub Actions (dépôt public) | 0 € |
| Supabase (offre gratuite actuelle) | 0 € |
| Cloudflare R2 (≈ 30 vidéos × 5-10 Mo, sous 10 Go) | 0 € (une carte bancaire est demandée pour activer R2, sans prélèvement sous le seuil gratuit) |
| Claude API (≈ 30 textes/mois, Opus 5.5) | ≈ 1 € |
| Musique, montage, polices libres | 0 € |
| API YouTube, Instagram, TikTok | 0 € |
| **Total** | **≈ 1 € / mois** |

Options payantes, seulement si besoin et après accord :
- service tiers de publication (déjà audité par TikTok) si l'audit traîne : ≈ 20 à 50 €/mois ;
- voix off de synthèse : ≈ 5 à 20 €/mois ;
- publicité payante sur les réseaux (« boost ») : budget libre.

Une limite de dépense sera posée sur la clé Claude (par exemple 5 $/mois).

## 4. Comptes à créer (par toi : identité, double authentification, conditions à accepter)

Avec l'adresse e-mail dédiée à BOYGAMES, dans cet ordre :

1. **Google** (si l'adresse n'en est pas déjà un) → **chaîne YouTube « BOYGAMES »** → **projet Google Cloud** avec
   l'API YouTube Data v3. Je te guiderai pour l'écran de consentement OAuth, puis tu autoriseras l'application une fois.
2. **Instagram** « boygames » passé en **compte professionnel**, relié à une **Page Facebook** BOYGAMES →
   **compte développeur Meta** + application (je prépare le dossier ; tu valides la connexion une fois).
3. **TikTok** « boygames » (compte professionnel) → **TikTok for Developers** + application avec le produit
   « Content Posting API » → demande d'audit (je rédige le dossier et la vidéo de démonstration).
4. **Console Anthropic** (clé API pour les textes, avec plafond de dépense) — facultatif au début.
5. **Cloudflare R2** : à activer sur le compte Cloudflare existant (carte bancaire demandée par Cloudflare).

Je ne crée aucun compte et ne saisis aucun mot de passe : tu fais les inscriptions et les validations d'identité ;
je fais tout le reste (configuration, code, secrets rangés dans GitHub, jamais dans le code).

## 5. Étapes suivantes

| Étape | Qui | Dépense |
|---|---|---|
| A. Prototype de fabrication (fait) | Claude | 0 € |
| B. Fabrication quotidienne dans le cloud (fichier prêt, inactif tant qu'il n'est pas sur `main`) | accord de Quentin pour l'activer | 0 € |
| C. File `marketing_videos` + onglet Marketing (aperçu, valider/refuser, calendrier) | Claude, en TEST | 0 € |
| D. Comptes YouTube / Instagram / TikTok (section 4) | Quentin | 0 € |
| E. Publication YouTube puis Instagram (après validation humaine) | Claude, après accord | 0 € |
| F. Audit TikTok | Claude prépare, Quentin envoie | 0 € |
| G. Suivi : vues, abonnés, visites et inscriptions par réseau | Claude | 0 € |
| H. Mode automatique | après plusieurs semaines sans erreur, sur accord | 0 € |

### Revenus directs des plateformes (sans rien supposer)
- YouTube : Programme Partenaire à partir de seuils d'abonnés et de vues de Shorts ; non acquis.
- TikTok : programmes de rémunération réservés à certains pays, âges et vidéos plus longues ; à vérifier le moment venu.
- Instagram : pas de rémunération générale des Reels ; bonus ponctuels selon les pays.
L'objectif réaliste au début est l'**acquisition de joueurs** pour BOYGAMES, mesurée par les liens suivis.

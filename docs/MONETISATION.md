# Monétisation BOYGAMES : préparation technique (phase 4)

**État : préparé sur TEST uniquement. Aucune publicité réelle, aucun paiement, aucun abonnement réel.**
Tout se règle dans Administration → « Monétisation (préparation) ». Migration : `sql/schema_v12_monetisation.sql`.

## A. Publicités

- 3 emplacements configurables, **tous hors partie** : accueil (sous les jeux), classements (en bas), boutique.
  Les écrans de jeu et de duel n'en contiennent aucun : impossible d'afficher une pub pendant une partie.
- Jamais de publicité pour un abonné Premium.
- Fournisseur actuel : `test` (cadre « emplacement publicitaire »). Prévu : `adsense` (à brancher le jour venu).
- **Avant toute vraie pub (UE)** : bannière de consentement (CMP certifiée) pour la publicité personnalisée,
  mise à jour de la politique de confidentialité, attention particulière aux mineurs (public jeune possible).

## B. Vidéos récompensées (continuation)

- Solo seulement, **Snake et Space Attack** (BoyBlocks et Block Drop : plus tard, voir ci-dessous).
- Après une défaite : bouton « CONTINUER · VIDÉO ». 1 continuation par partie (réglable 0 à 2), 10 vidéos par jour max.
- **Protection des classements** : la partie jusqu'à la défaite est enregistrée normalement (classement, record,
  missions, paliers). Le score final de la partie continuée va dans une table séparée (`scores_continued`) :
  il ne compte **ni au classement, ni aux records, ni aux missions, ni aux paliers**. Il rapporte 5 XP de participation,
  0 BC (réglable jusqu'à 5 BC, à n'activer qu'après équilibrage).
- Premium : continuation sans vidéo imposée (toujours hors classement : aucun avantage compétitif).
- Chaque vidéo est tracée côté base (`ad_events`) avec limite quotidienne.
- BoyBlocks : son score est vérifié en rejouant la partie côté base ; une continuation demande d'ajouter une règle
  « reprise » au moteur JS et SQL. Faisable, mais à décider (le mode reste sinon parfaitement vérifiable).
- Fournisseur à prévoir : une régie qui propose la vidéo récompensée sur le web (par exemple Google H5 Games Ads,
  sur dossier). Aujourd'hui : vidéo de test de 5 secondes, rien n'est diffusé.

## C. BOYGAMES Premium (0,99 €/mois envisagé)

- Avantages : pas de pub imposée, badge **PREMIUM** à côté du pseudo (profil, fiche publique), cosmétiques réservés
  (`shop_items.premium_only`), cadeaux cosmétiques. **Aucun avantage en jeu** (vérifié : aucune fonction de score ne lit
  le statut Premium).
- Badge **PIONNIER PREMIUM** : donné aux N premiers abonnés (réglable, 100 par défaut), exclusif, conservé à vie même
  après résiliation, distinct du badge Premium actif et des badges Fondateur / Bêta.
- Table `premium_subscriptions` prête pour un vrai prestataire (`source` : stripe, apple, google). Aujourd'hui seule la
  source `test` existe : l'équipe peut simuler un abonnement depuis l'administration.
- Carte Premium sur la page Profil quand l'offre est affichée, bouton « BIENTÔT DISPONIBLE » (aucun paiement possible).

### Ordre de grandeur des coûts d'un abonnement à 0,99 € (à vérifier avant lancement)

| | Montant |
|---|---|
| Prix TTC | 0,99 € |
| TVA 20 % | ≈ 0,165 € |
| Frais carte en ligne (type Stripe, UE, ~1,5 % + 0,25 €) | ≈ 0,26 € |
| **Reste par mois** | **≈ 0,56 €** |

Les frais fixes par paiement pèsent lourd sur un petit montant : un tarif annuel (par exemple 9,99 €/an) ou un
passage par les boutiques d'applications (commission réduite pour les petits éditeurs) serait à comparer.

## Pour aller plus loin (décisions à prendre)

1. Choisir la régie publicitaire et la solution de consentement.
2. Choisir le prestataire de paiement (web) ou une application iOS/Android.
3. Décider si les continuations rapportent un peu de BC.
4. Décider de la continuation pour BoyBlocks.

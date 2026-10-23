/* Réglages Google AdSense de BOYGAMES. Ces valeurs sont publiques (elles apparaissent dans toute page avec publicité) :
   aucune clé secrète ici.
   TANT QUE Google n'a pas approuvé le site, laisser enabled ET approved à false : aucun script publicitaire ni bannière
   de consentement n'est chargé, et les emplacements restent cachés. Voir docs/ADSENSE.md avant toute modification. */
window.BG_PUB_CONFIG = {
  enabled: false,          // interrupteur général du code AdSense sur ce site
  approved: false,         // à passer à true seulement quand Google a approuvé le site (compte AdSense → Sites)
  publisherId: "",         // identifiant éditeur, forme « ca-pub- » + 16 chiffres (à fournir par Quentin, ne rien inventer)
  slots: {                 // identifiants des blocs d'annonces créés dans AdSense (chiffres seulement), un par emplacement
    home: "",              // accueil, sous la liste des jeux
    scores: "",            // classements, en bas de la liste
    shop: ""               // boutique, en bas
  },
  underAgeOfConsent: true  // public potentiellement jeune : annonces non personnalisées pour tout le monde (TFUA)
};

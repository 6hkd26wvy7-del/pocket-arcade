// Accroche, légende et hashtags de chaque vidéo.
// Avec une clé Claude (ANTHROPIC_API_KEY), le texte est écrit par Claude à partir des vrais chiffres de la partie et de
// l'historique des vidéos précédentes (pour ne pas se répéter). Sans clé : modèles variés, choisis au hasard.
import Anthropic from "@anthropic-ai/sdk";

const MODELES = [
  { accroche: "Ce combo x{combo}", legende: "{lignes} lignes effacées, {score} points. Tu fais mieux ?" },
  { accroche: "Satisfaisant jusqu'au bout", legende: "Une partie de BoyBlocks sans pause : {score} points." },
  { accroche: "{score} points. À toi.", legende: "Glisse, efface, enchaîne. Gratuit, sans pub dans les parties." },
  { accroche: "La grille se vide…", legende: "{lignes} lignes, combo x{combo}. Le défi t'attend sur BOYGAMES." },
  { accroche: "Défi : bats {score}", legende: "Une vraie partie, un vrai score. Montre-nous ton record sur BOYGAMES." },
  { accroche: "{lignes} lignes d'affilée", legende: "Pose, efface, recommence. BoyBlocks, gratuit sur BOYGAMES." },
  { accroche: "Combo x{combo}, sans tricher", legende: "Chaque score est vérifié par le serveur. À ton tour." },
  { accroche: "Le calme avant le combo", legende: "{score} points en {coups} coups. Et toi ?" },
  { accroche: "Tu tiens combien de coups ?", legende: "Celle-ci a duré {coups} coups pour {score} points. BOYGAMES, gratuit." },
  { accroche: "Zéro pub pendant la partie", legende: "Juste toi et la grille. BoyBlocks sur BOYGAMES." },
];
const HASHTAGS = ["#BOYGAMES", "#BoyBlocks", "#jeumobile", "#puzzle", "#satisfaisant", "#gaming", "#jeuxvideo", "#blockpuzzle"];

const SCHEMA = {
  type: "object",
  properties: {
    accroche: { type: "string", description: "Texte à l'écran, 3 premières secondes, 40 caractères max" },
    legende: { type: "string", description: "Légende de la publication, 150 caractères max, sans hashtag" },
    hashtags: { type: "array", items: { type: "string" }, description: "5 à 8 hashtags pertinents" },
  },
  required: ["accroche", "legende", "hashtags"],
  additionalProperties: false,
};

function remplir(s, p) { return s.replace(/\{(\w+)\}/g, (_, k) => String(p[k] ?? "")); }

export async function ecrireTextes(partie, { historique = [], graine = 1 } = {}) {
  if (process.env.ANTHROPIC_API_KEY) {
    const client = new Anthropic();
    const response = await client.beta.messages.create({
      model: "claude-opus-5-5",
      max_tokens: 2000,
      betas: ["server-side-fallback-2026-07-01"],
      fallbacks: "default",
      output_config: { effort: "low", format: { type: "json_schema", schema: SCHEMA } },
      system: "Tu écris les textes de courtes vidéos verticales (TikTok, Reels, Shorts) pour BOYGAMES, une plateforme française de jeux gratuits. " +
        "Ton direct, jeune, positif, en français. Jamais de fausse promesse, jamais de gain d'argent, pas de vocabulaire de jeu d'argent. " +
        "Les chiffres donnés sont réels : utilise-les tels quels.",
      messages: [{ role: "user", content:
        `Partie réelle de BoyBlocks : ${partie.score} points, ${partie.lignes} lignes effacées, meilleur combo x${partie.combo}, ${partie.coups} coups.\n` +
        `Accroches déjà utilisées (ne pas les répéter ni les paraphraser) :\n${historique.slice(-20).map((h) => "- " + h).join("\n") || "- aucune"}` }],
    });
    if (response.stop_reason !== "refusal") {
      const txt = response.content.find((b) => b.type === "text");
      if (txt) { const out = JSON.parse(txt.text); return { ...out, source: "claude-opus-5-5" }; }
    }
  }
  const m = MODELES[graine % MODELES.length];
  const tags = [...HASHTAGS].sort((a, b) => ((a.length * 31 + graine) % 7) - ((b.length * 31 + graine) % 7)).slice(0, 6);
  return { accroche: remplir(m.accroche, partie), legende: remplir(m.legende, partie), hashtags: tags, source: "modèles" };
}

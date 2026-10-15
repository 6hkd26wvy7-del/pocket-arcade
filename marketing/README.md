# Marketing BOYGAMES

Fabrication automatique de vidéos 9:16 à partir de vraies parties. Rien n'est publié par ces scripts.

```
npm install                      # une fois (ffmpeg, navigateur, SDK Claude)
npx playwright install chromium  # une fois
python3 -I ../build.py           # assemble le site depuis src/
node fabriquer-video.mjs 45      # → sortie/<date>-45/video.mp4 + infos.json
```

- `capturer.mjs` : choisit une belle partie de BoyBlocks (simulation du vrai moteur) et la filme sur le vrai site.
- `textes.mjs` : accroche, légende, hashtags (Claude si `ANTHROPIC_API_KEY`, sinon modèles).
- `musique.mjs` : musique chiptune générée (aucun droit).
- `fabriquer-video.mjs` : montage ffmpeg.
- Cloud : `.github/workflows/marketing-video.yml` (inactif tant qu'il n'est pas sur `main`).
- Conception, devis, comptes : `../docs/MARKETING.md`.

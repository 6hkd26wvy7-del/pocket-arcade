# Diagnostics

- `space-attack-227500-vague64-capture.png` : fin de partie Space Attack fournie par le joueur (score 227 500, REC 227500, vague 64,
  « Score enregistré. +65 XP, +5 BOYCOINS. »). Pièce du bug du 19/10 (record bloqué à 100 000 par la troncature v17).
  Correctif : PR #5 (migration v25, tests `sql/test/space_plafond.test.mjs`). Restauration du record : `sql/admin_restauration_record_space.sql` (non exécuté).

-- OPÉRATION ADMINISTRATIVE EXCEPTIONNELLE — restauration du record Space Attack à 227 500 (capture du 19/10/2026, vague 64).
-- NON EXÉCUTÉE. À lancer seulement après accord explicite du propriétaire, d'abord sur TEST (xgoqwxvgiavajnygoblt) :
-- la production (rvygnqpagbmiqbdkwlfp) est figée au 14/10 et n'a ni les tickets v22 ni le plafond v17, elle n'est donc pas concernée.
--
-- Principe : la partie réelle a été envoyée tronquée à 100 000 (bug v17). Il existe donc UNE ligne `scores` de 100 000 pour cette
-- partie. On corrige cette ligne (100 000 -> 227 500) : aucune partie fictive créée, XP / BOYCOINS / niveau / ledger intouchés,
-- protections générales intactes. L'opération est journalisée dans `admin_actions` (action 'restauration_record_space').
--
-- MODE D'EMPLOI
--   1. Remplacer tintintest ci-dessous (3 occurrences) par le pseudo exact.
--   2. Étape A (lecture seule) : exécuter seule, vérifier qu'il y a UNE ligne à 100000 récente et pas de partie correspondante douteuse.
--   3. Étape B : exécuter d'un seul bloc. Elle finit par ROLLBACK (aucun effet) et affiche les contrôles.
--      Pour appliquer pour de bon : remplacer la dernière instruction `rollback;` par `commit;`.
--   4. Étape C (lecture seule) : contrôler profil et classements.

-- ===== ÉTAPE A — vérification en lecture seule =====
select p.id, p.pseudo, p.country, ps.xp, ps.level, ps.bc from public.profiles p left join public.player_stats ps on ps.user_id = p.id where p.pseudo = 'tintintest';
select s.id, s.score, s.created_at from public.scores s join public.profiles p on p.id = s.user_id where p.pseudo = 'tintintest' and s.game = 'space' order by s.created_at desc limit 20;
select g.id, g.started_at, g.used_at, extract(epoch from g.used_at - g.started_at)::int as duree_s from public.game_runs g join public.profiles p on p.id = g.user_id where p.pseudo = 'tintintest' and g.game = 'space' order by g.started_at desc limit 10;
select l.delta, l.reason, l.created_at from public.bc_ledger l join public.profiles p on p.id = l.user_id where p.pseudo = 'tintintest' order by l.created_at desc limit 10;
select rang, pseudo, score from public.leaderboard('space', null, 100) where pseudo = 'tintintest';

-- ===== ÉTAPE B — correction transactionnelle (ROLLBACK par défaut) =====
begin;
do $$
declare cible record; n int;
begin
  select s.id, s.user_id into cible from public.scores s join public.profiles p on p.id = s.user_id
   where p.pseudo = 'tintintest' and s.game = 'space' and s.score = 100000
   order by s.created_at desc limit 1;
  if not found then raise exception 'ABANDON : aucune ligne Space à 100000 pour ce pseudo (rien à corriger)'; end if;
  update public.scores set score = 227500 where id = cible.id and score = 100000;
  get diagnostics n = row_count;
  if n <> 1 then raise exception 'ABANDON : la correction doit toucher exactement une ligne (%)', n; end if;
  insert into public.admin_actions (by_user, target_user, action, detail)
  values (null, cible.user_id, 'restauration_record_space',
          jsonb_build_object('score_id', cible.id, 'ancien', 100000, 'nouveau', 227500, 'cause', 'troncature v17 corrigée en v25',
                             'preuve', 'docs/diagnostics/space-attack-227500-vague64-capture.png', 'xp_bc_modifies', false));
end $$;
-- contrôles dans la transaction : le record Space est 227500, XP/BC inchangés (comparer avec l'étape A)
select p.pseudo, max(s.score) as record_space, count(*) as parties from public.scores s join public.profiles p on p.id = s.user_id where p.pseudo = 'tintintest' and s.game = 'space' group by p.pseudo;
select ps.xp, ps.level, ps.bc from public.player_stats ps join public.profiles p on p.id = ps.user_id where p.pseudo = 'tintintest';
rollback;   -- <- remplacer par `commit;` pour appliquer, après accord explicite

-- ===== ÉTAPE C — visibilité (après un commit) =====
-- select rang, pseudo, score from public.leaderboard('space', null, 100) where pseudo = 'tintintest';            -- monde
-- select rang, pseudo, score from public.leaderboard('space', 'FR', 100) where pseudo = 'tintintest';           -- pays (adapter)
-- select rang, pseudo, score from public.leaderboard_season('space', null, 100) where pseudo = 'tintintest';    -- saison (si la ligne est dans la saison)
-- select public.public_profile('tintintest');                                                                   -- fiche profil

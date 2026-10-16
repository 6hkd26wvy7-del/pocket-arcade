-- BOYGAMES — MIGRATION v17 : plafond de score Space Attack 20 000 -> 100 000 (TEST)
-- À lancer APRÈS la v16. Tout-ou-rien, relançable. Ne touche à aucune donnée existante.
-- Raison : depuis les bonus (phase 1), une bonne partie dépasse 20 000 ; le score était bloqué au plafond
-- (signalement n°1 du 15/10 « Score non enregistré sur Space attack »). Snake et Block Drop inchangés.
begin;

do $$ begin
  if to_regclass('public.beta_missions') is null then
    raise exception 'PRE-CONTROLE : la migration v16 doit être lancée AVANT celle-ci. Rien n''a été modifié.';
  end if;
end $$;

do $$
begin
  perform set_config('boygames.mig_tx', txid_current()::text, true);
  perform set_config('boygames.mig_before', (jsonb_build_object(
    'scores', (select count(*) from public.scores), 'sum_bc', (select coalesce(sum(bc), 0) from public.player_stats),
    'sum_xp', (select coalesce(sum(xp), 0) from public.player_stats), 'user_badges', (select count(*) from public.user_badges)))::text, true);
end $$;
do $$
begin
  if coalesce(current_setting('boygames.mig_tx', true), '') <> txid_current()::text
     or coalesce(current_setting('boygames.mig_before', true), '') = '' then
    raise exception 'EXECUTION EN PLUSIEURS MORCEAUX : ce script doit etre lance en entier, d''un seul bloc. Rien n''a ete modifie.';
  end if;
end $$;

create or replace function public.game_max_score(p_game text)
returns int language sql immutable as $$
  select case p_game
    when 'snake' then 429
    when 'blocks' then 50000
    when 'space' then 100000
    else 0
  end;
$$;
revoke all on function public.game_max_score(text) from public, anon, authenticated;

do $$
declare b jsonb; a jsonb := jsonb_build_object(
    'scores', (select count(*) from public.scores), 'sum_bc', (select coalesce(sum(bc), 0) from public.player_stats),
    'sum_xp', (select coalesce(sum(xp), 0) from public.player_stats), 'user_badges', (select count(*) from public.user_badges));
begin
  if coalesce(current_setting('boygames.mig_tx', true), '') <> txid_current()::text then
    raise exception 'EXECUTION EN PLUSIEURS MORCEAUX : relancer le script en entier, d''un seul bloc.';
  end if;
  b := current_setting('boygames.mig_before')::jsonb;
  if a is distinct from b then raise exception 'GARDE-FOU : des donnees existantes auraient change (% -> %). Rien n''a ete applique.', b, a; end if;
  if public.game_max_score('space') <> 100000 or public.game_max_score('snake') <> 429 or public.game_max_score('blocks') <> 50000
     or has_function_privilege('authenticated', 'public.game_max_score(text)', 'execute') then
    raise exception 'GARDE-FOU : plafonds ou droits inattendus. Rien n''a été appliqué.';
  end if;
end $$;

commit;

select 'Migration v17 appliquée (plafond Space Attack 100 000)' as resultat, public.game_max_score('space') as plafond_space;

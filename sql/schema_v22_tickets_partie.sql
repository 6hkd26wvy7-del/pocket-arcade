-- BOYGAMES — MIGRATION v22 : ticket de partie et vraisemblance des scores solo (Snake, Space Attack, Block Drop) (TEST)
-- À lancer APRÈS la v21. Tout-ou-rien, relançable. Ne modifie aucune donnée existante (scores, XP, BC conservés).
-- Avant : le téléphone envoyait son score sans contrôle de durée (on pouvait inscrire 429 à Snake en une seconde).
-- Maintenant : la base remet un ticket au début de la partie (game_start) ; le score n'est accepté qu'avec ce ticket,
-- une seule fois, et seulement s'il est possible dans le temps réellement écoulé (bornes LARGES, mesurées le 19/10).
-- L'ancienne fonction submit_score n'est plus appelable par les joueurs ; elle reste utilisée en interne.
-- BoyBlocks a déjà sa propre vérification complète (rejeu des coups), inchangée.
begin;

do $$ begin
  if to_regclass('public.admin_actions') is null then
    raise exception 'PRE-CONTROLE : les migrations v20 et v21 doivent être lancées AVANT celle-ci. Rien n''a été modifié.';
  end if;
end $$;

do $$
begin
  perform set_config('boygames.mig_tx', txid_current()::text, true);
  perform set_config('boygames.mig_before', (jsonb_build_object(
    'scores', (select count(*) from public.scores), 'bc_ledger', (select count(*) from public.bc_ledger),
    'sum_bc', (select coalesce(sum(bc), 0) from public.player_stats), 'sum_xp', (select coalesce(sum(xp), 0) from public.player_stats),
    'user_badges', (select count(*) from public.user_badges)))::text, true);
end $$;
do $$
begin
  if coalesce(current_setting('boygames.mig_tx', true), '') <> txid_current()::text
     or coalesce(current_setting('boygames.mig_before', true), '') = '' then
    raise exception 'EXECUTION EN PLUSIEURS MORCEAUX : ce script doit etre lance en entier, d''un seul bloc. Rien n''a ete modifie.';
  end if;
end $$;

create table if not exists public.game_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  game text not null check (game in ('snake', 'space', 'blocks')),
  started_at timestamptz not null default now(),
  used_at timestamptz
);
create index if not exists game_runs_user on public.game_runs (user_id, started_at desc);
alter table public.game_runs enable row level security;
revoke all on public.game_runs from anon, authenticated;

-- Score maximal vraisemblable pour une durée donnée (en secondes). Volontairement large : ne refuse que l'impossible.
create or replace function public.score_plausible(p_game text, p_score int, p_seconds numeric) returns boolean
language plpgsql immutable as $$
declare k int; total bigint := 0;
begin
  if p_game = 'snake' then
    return p_score * 0.26 <= p_seconds + 2;                 -- vitesse max : 130 ms par case, au moins 2 cases par pomme
  elsif p_game = 'space' then
    return p_score <= 500 + p_seconds * 3000;              -- mesuré : ~2 700 pts/s avec 2 vaisseaux Difficile et bonus
  elsif p_game = 'blocks' then
    for k in 1 .. greatest(1, floor(p_seconds / 2)::int + 1) loop   -- un tétris toutes les 2 s, au niveau atteint
      total := total + 800 * (1 + floor(0.4 * (k - 1)));
      exit when total > p_score;
    end loop;
    return p_score <= total + 2000;                        -- + points de descente rapide
  end if;
  return false;
end $$;

-- Début de partie : ticket à usage unique
create or replace function public.game_start(p_game text) returns uuid language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); rid uuid;
begin
  perform public.guard_action(uid);
  if p_game not in ('snake', 'space', 'blocks') then raise exception 'unknown game'; end if;
  if (select count(*) from public.game_runs where user_id = uid and started_at > now() - interval '10 minutes') >= 60 then raise exception 'too many'; end if;
  delete from public.game_runs where user_id = uid and started_at < now() - interval '1 day';    -- ménage des vieux tickets
  insert into public.game_runs (user_id, game) values (uid, p_game) returning id into rid;
  return rid;
end $$;

-- Fin de partie : contrôle du ticket et de la vraisemblance, puis enregistrement habituel (submit_score)
create or replace function public.submit_score_v2(p_game text, p_score int, p_run uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r public.game_runs; secs numeric;
begin
  perform public.guard_action(uid);
  select * into r from public.game_runs where id = p_run for update;
  if not found or r.user_id <> uid or r.game <> p_game or r.used_at is not null then raise exception 'invalid run'; end if;
  if r.started_at < now() - interval '3 hours' then raise exception 'invalid run'; end if;
  secs := extract(epoch from now() - r.started_at);
  update public.game_runs set used_at = now() where id = p_run;
  if not public.score_plausible(p_game, p_score, secs) then raise exception 'implausible score'; end if;
  return public.submit_score(p_game, p_score);
end $$;

revoke all on function public.score_plausible(text, int, numeric) from public, anon, authenticated;
revoke all on function public.game_start(text), public.submit_score_v2(text, int, uuid) from public, anon;
grant execute on function public.game_start(text), public.submit_score_v2(text, int, uuid) to authenticated;
revoke execute on function public.submit_score(text, int) from public, anon, authenticated;     -- plus d'envoi direct

do $$
declare b jsonb; a jsonb := jsonb_build_object(
    'scores', (select count(*) from public.scores), 'bc_ledger', (select count(*) from public.bc_ledger),
    'sum_bc', (select coalesce(sum(bc), 0) from public.player_stats), 'sum_xp', (select coalesce(sum(xp), 0) from public.player_stats),
    'user_badges', (select count(*) from public.user_badges));
begin
  if coalesce(current_setting('boygames.mig_tx', true), '') <> txid_current()::text then
    raise exception 'EXECUTION EN PLUSIEURS MORCEAUX : relancer le script en entier, d''un seul bloc.';
  end if;
  b := current_setting('boygames.mig_before')::jsonb;
  if a is distinct from b then raise exception 'GARDE-FOU : des donnees existantes auraient change (% -> %). Rien n''a ete applique.', b, a; end if;
  if has_function_privilege('authenticated', 'public.submit_score(text,int)', 'execute')
     or has_function_privilege('anon', 'public.game_start(text)', 'execute')
     or has_table_privilege('authenticated', 'public.game_runs', 'select')
     or not public.score_plausible('snake', 100, 60) or public.score_plausible('snake', 429, 5)
     or public.score_plausible('space', 100000, 10) or not public.score_plausible('blocks', 14100, 300) then
    raise exception 'GARDE-FOU : droits ou bornes inattendus. Rien n''a été appliqué.';
  end if;
end $$;

commit;

select 'Migration v22 appliquée (tickets de partie, scores vraisemblables)' as resultat;

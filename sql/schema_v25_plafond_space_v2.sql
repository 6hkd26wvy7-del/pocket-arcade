-- BOYGAMES — MIGRATION v25 : plafond absolu de score Space Attack 100 000 -> 5 000 000 (TEST, préparée, NON appliquée)
-- À lancer APRÈS la v23 (la v24 des invitations est indépendante). Tout-ou-rien, relançable. Ne modifie aucune donnée.
-- Raison : le site tronquait tout score Space au-dessus de 100 000 à exactement 100 000 avant l'envoi (plafond de la v17),
-- donc les très bonnes parties étaient enregistrées à 100 000 et le vrai score perdu.
-- La protection anti-triche ne change pas : ticket de partie à usage unique + vraisemblance liée à la durée
-- (score_plausible : 500 + 3 000 points par seconde, v22). Ce plafond n'est plus qu'un garde-fou absolu ; gains d'XP et de
-- BOYCOINS inchangés (XP plafonnée à 60 par partie, BOYCOINS plafonnés par les réglages d'économie).
-- Ajouts du 20/10 (capture à 227 500 points) :
--  * submit_score_v2 renvoie aussi `score` (valeur stockée) et `best` (meilleur score en ligne) : le site n'affiche « Score enregistré »
--    qu'avec la valeur confirmée par la base ;
--  * submit_continued_score exige une continuation réellement accordée (rewarded_continue, usage unique, 3 h) : plus de récompense
--    de participation rejouable à la main sans vidéo.
begin;

do $$ begin
  if to_regclass('public.ad_events') is null or to_regprocedure('public.submit_continued_score(text,integer,integer)') is null then
    raise exception 'PRE-CONTROLE : la migration v12 (monétisation) doit être présente. Rien n''a été modifié.';
  end if;
  if to_regprocedure('public.score_plausible(text,integer,numeric)') is null then
    raise exception 'PRE-CONTROLE : la migration v22 doit être lancée AVANT celle-ci. Rien n''a été modifié.';
  end if;
end $$;

create or replace function public.game_max_score(p_game text)
returns int language sql immutable as $$
  select case p_game
    when 'snake' then 429
    when 'blocks' then 50000
    when 'space' then 5000000   -- v25 : 100 000 avant (le site tronquait les scores à 100 000)
    else 0
  end;
$$;
revoke all on function public.game_max_score(text) from public;

do $$ begin
  if public.game_max_score('space') <> 5000000 or public.game_max_score('snake') <> 429 or public.game_max_score('blocks') <> 50000
     or public.game_max_score('autre') <> 0 then
    raise exception 'GARDE-FOU : plafonds inattendus. Rien n''a été appliqué.';
  end if;
end $$;

alter table public.ad_events add column if not exists used_at timestamptz;

create or replace function public.submit_score_v2(p_game text, p_score int, p_run uuid) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r public.game_runs; secs numeric; res jsonb; top int;
begin
  perform public.guard_action(uid);
  select * into r from public.game_runs where id = p_run for update;
  if not found or r.user_id <> uid or r.game <> p_game or r.used_at is not null then raise exception 'invalid run'; end if;
  if r.started_at < now() - interval '3 hours' then raise exception 'invalid run'; end if;
  secs := extract(epoch from now() - r.started_at);
  update public.game_runs set used_at = now() where id = p_run;
  if not public.score_plausible(p_game, p_score, secs) then raise exception 'implausible score'; end if;
  -- v25 : la réponse porte le score réellement stocké et le meilleur score en ligne, pour que le site n'affiche « Score enregistré » qu'avec la valeur confirmée
  res := public.submit_score(p_game, p_score);     -- d'abord l'enregistrement, puis la lecture du record (ordre explicite)
  select max(score) into top from public.scores where user_id = uid and game = p_game;
  return res || jsonb_build_object('score', p_score, 'best', top);
end $$;

create or replace function public.submit_continued_score(p_game text, p_score int, p_continues int) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r jsonb := public.monet('rewarded'); last_at timestamptz; xp_gain int; bc_gain int := 0;
  before_level int; after_level int; max_allowed int;
begin
  perform public.guard_action(uid);
  if r is null or not (r -> 'games') ? p_game then raise exception 'game not eligible'; end if;
  max_allowed := public.game_max_score(p_game);
  if max_allowed = 0 then raise exception 'unknown game'; end if;
  if p_score is null or p_score < 0 or p_score > max_allowed then raise exception 'invalid score'; end if;
  if p_continues is null or p_continues < 1 or p_continues > least(5, coalesce((r ->> 'continue_max')::int, 1)) then raise exception 'invalid continues'; end if;
  select max(created_at) into last_at from public.scores_continued where user_id = uid;
  if last_at is not null and last_at > now() - interval '8 seconds' then raise exception 'too fast'; end if;
  -- v25 : chaque score de partie continuée consomme UNE continuation réellement accordée (rewarded_continue) : sans elle, pas de récompense
  update public.ad_events set used_at = now()
   where id = (select id from public.ad_events where user_id = uid and kind = 'rewarded_continue' and game = p_game
                  and used_at is null and created_at > now() - interval '3 hours' order by id limit 1 for update skip locked);
  if not found then raise exception 'no continue'; end if;
  insert into public.player_stats (user_id) values (uid) on conflict do nothing;
  insert into public.scores_continued (user_id, game, score, continues) values (uid, p_game, p_score, p_continues);
  xp_gain := 5;                                                    -- XP de participation seulement
  bc_gain := greatest(0, least(coalesce((r ->> 'bc_per_continue')::int, 0), 5));
  select level into before_level from public.player_stats where user_id = uid;
  perform public.add_xp(uid, xp_gain);
  if bc_gain > 0 then perform public.add_bc(uid, bc_gain, 'continue'); end if;
  select level into after_level from public.player_stats where user_id = uid;
  return jsonb_build_object('xp', xp_gain, 'bc', bc_gain, 'level', after_level, 'level_up', after_level > before_level, 'ranked', false);
end $$;

commit;
select 'Migration v25 appliquée (plafond Space Attack 5 000 000)' as resultat, public.game_max_score('space') as plafond_space;

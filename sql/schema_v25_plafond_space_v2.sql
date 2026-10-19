-- BOYGAMES — MIGRATION v25 : scores sans plafond arbitraire (TEST, préparée, NON appliquée)
-- À lancer APRÈS la v23 (la v24 des invitations est indépendante). Tout-ou-rien, relançable. Ne supprime ni ne modifie aucun score.
-- Raison : le site tronquait tout score Space au-dessus de 100 000 à exactement 100 000 avant l'envoi (plafond de la v17), donc les
-- très bonnes parties (227 500, vague 64, le 19/10) étaient enregistrées à 100 000 et le vrai score perdu.
-- Nouvelle règle (décision du 19/10) : plus aucun plafond fixe arbitraire pour Space. Types : score bigint partout (scores,
-- scores_continued, classements, paramètres des fonctions) ; seule limite technique : 9 007 199 254 740 991 (2^53 - 1), le plus grand
-- entier exact côté JavaScript (et JSON). Au-delà : refus explicite 'invalid score', jamais de troncature.
-- Anti-triche inchangée : ticket de partie à usage unique + vraisemblance liée à la durée (score_plausible : 500 + 3 000 points par
-- seconde pour Space, ticket valable 3 h). Gains d'XP (60 max) et BOYCOINS (barème et plafond journalier) inchangés.
-- Autres ajouts : submit_score_v2 renvoie `score` (stocké) et `best` (record) ; submit_continued_score exige une continuation réellement
-- accordée (rewarded_continue, usage unique) ; my_missions écrête sa progression à 2^31 - 1 (objectifs très inférieurs).
-- Limites conservées et signalées : Snake 429 (maximum de la grille), Block Drop 50 000, BoyBlocks (rejeu complet, colonne integer).
begin;

do $$ begin
  if to_regclass('public.ad_events') is null or (to_regprocedure('public.submit_continued_score(text,integer,integer)') is null and to_regprocedure('public.submit_continued_score(text,bigint,integer)') is null) then
    raise exception 'PRE-CONTROLE : la migration v12 (monétisation) doit être présente. Rien n''a été modifié.';
  end if;
  if to_regprocedure('public.score_plausible(text,integer,numeric)') is null and to_regprocedure('public.score_plausible(text,bigint,numeric)') is null then
    raise exception 'PRE-CONTROLE : la migration v22 doit être lancée AVANT celle-ci. Rien n''a été modifié.';
  end if;
end $$;

alter table public.ad_events add column if not exists used_at timestamptz;     -- continuation consommée par submit_continued_score
alter table public.scores alter column score type bigint;
alter table public.scores_continued alter column score type bigint;
alter table public.scores drop constraint if exists scores_score_safe;
alter table public.scores add constraint scores_score_safe check (score <= 9007199254740991);
alter table public.scores_continued drop constraint if exists scores_continued_score_safe;
alter table public.scores_continued add constraint scores_continued_score_safe check (score <= 9007199254740991);

drop function if exists public.submit_score_v2(text, integer, uuid);
drop function if exists public.submit_continued_score(text, integer, integer);
drop function if exists public.submit_score(text, integer);
drop function if exists public.score_plausible(text, integer, numeric);
drop function if exists public.bc_for_score(text, integer);
drop function if exists public.game_max_score(text);
drop function if exists public.leaderboard(text, text, integer);
drop function if exists public.leaderboard_friends(text, integer);
drop function if exists public.leaderboard_season(text, text, integer);
drop function if exists public.my_standing(text, text);

create or replace function public.game_max_score(p_game text)
returns bigint language sql immutable as $$
  -- Aucun plafond arbitraire pour Space : seule borne = plus grand entier exact en JavaScript (Number.MAX_SAFE_INTEGER, 2^53 - 1).
  -- Snake : 429 = cases de la grille (18 x 24) moins le serpent de départ (3), maximum réel. Blocks : 50 000 inchangé (voir README/PR).
  -- La vraisemblance (score_plausible : durée de la partie) reste la protection contre la triche.
  select case p_game
    when 'snake' then 429::bigint
    when 'blocks' then 50000::bigint
    when 'space' then 9007199254740991::bigint
    else 0::bigint
  end;
$$;

create or replace function public.bc_for_score(p_game text, p_score bigint)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare g jsonb := public.econ('game_bc') -> p_game; v bigint;
begin
  if g is null then return 1; end if;
  v := p_score / greatest(1, (g ->> 'div')::int);
  if g ->> 'cap' is not null then v := least(v, (g ->> 'cap')::bigint); end if;
  return 1 + greatest(0, v)::int;
end $function$;

create or replace function public.score_plausible(p_game text, p_score bigint, p_seconds numeric)
 RETURNS boolean
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
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
end $function$;

create or replace function public.submit_score(p_game text, p_score bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  uid uuid := auth.uid();
  today date := (now() at time zone 'Europe/Paris')::date;
  max_allowed bigint;
  last_at timestamptz;
  xp_gain int;
  bc_gain int;
  earned_today int;
  before_level int;
  after_level int;
  badges text[];
begin
  perform public.guard_action(uid);
  if not exists (select 1 from public.profiles where id = uid) then raise exception 'no profile'; end if;

  max_allowed := public.game_max_score(p_game);
  if max_allowed = 0 then raise exception 'unknown game'; end if;
  if p_score is null or p_score < 0 or p_score > max_allowed then raise exception 'invalid score'; end if;   -- refus explicite, jamais de troncature

  select max(created_at) into last_at from public.scores where user_id = uid;
  if last_at is not null and last_at > now() - interval '8 seconds' then raise exception 'too fast'; end if;

  insert into public.player_stats (user_id) values (uid) on conflict do nothing;
  insert into public.scores (user_id, game, score) values (uid, p_game, p_score);

  -- Les gains sont ramenés à une échelle commune pour que tous les jeux rapportent à peu près pareil.
  xp_gain := 5 + case p_game when 'blocks' then least(p_score / 40, 60) when 'space' then least(p_score / 20, 60) else p_score / 2 end;
  bc_gain := public.bc_for_score(p_game, p_score);
  select coalesce(sum(delta), 0) into earned_today from public.bc_ledger
   where user_id = uid and reason = 'game' and (created_at at time zone 'Europe/Paris')::date = today;
  bc_gain := least(bc_gain, greatest(0, public.bc_daily_cap() - earned_today));

  select level into before_level from public.player_stats where user_id = uid;
  perform public.add_xp(uid, xp_gain);
  if bc_gain > 0 then perform public.add_bc(uid, bc_gain, 'game'); end if;
  select level into after_level from public.player_stats where user_id = uid;
  badges := public.check_badges(uid);

  return jsonb_build_object(
    'xp', xp_gain, 'bc', bc_gain,
    'level', after_level, 'level_up', after_level > before_level,
    'new_badges', to_jsonb(badges));
end;
$function$;

create or replace function public.submit_score_v2(p_game text, p_score bigint, p_run uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid := auth.uid(); r public.game_runs; secs numeric; res jsonb; top bigint;
begin
  perform public.guard_action(uid);
  select * into r from public.game_runs where id = p_run for update;
  if not found or r.user_id <> uid or r.game <> p_game or r.used_at is not null then raise exception 'invalid run'; end if;
  if r.started_at < now() - interval '3 hours' then raise exception 'invalid run'; end if;
  secs := extract(epoch from now() - r.started_at);
  update public.game_runs set used_at = now() where id = p_run;
  if not public.score_plausible(p_game, p_score, secs) then raise exception 'implausible score'; end if;
  res := public.submit_score(p_game, p_score);     -- d'abord l'enregistrement, puis la lecture du record (ordre explicite)
  select max(score) into top from public.scores where user_id = uid and game = p_game;
  return res || jsonb_build_object('score', p_score, 'best', top);   -- le site n'affiche « Score enregistré » qu'avec cette confirmation
end $function$;

create or replace function public.submit_continued_score(p_game text, p_score bigint, p_continues integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare uid uuid := auth.uid(); r jsonb := public.monet('rewarded'); last_at timestamptz; xp_gain int; bc_gain int := 0;
  before_level int; after_level int; max_allowed bigint;
begin
  perform public.guard_action(uid);
  if r is null or not (r -> 'games') ? p_game then raise exception 'game not eligible'; end if;
  max_allowed := public.game_max_score(p_game);
  if max_allowed = 0 then raise exception 'unknown game'; end if;
  if p_score is null or p_score < 0 or p_score > max_allowed then raise exception 'invalid score'; end if;
  if p_continues is null or p_continues < 1 or p_continues > least(5, coalesce((r ->> 'continue_max')::int, 1)) then raise exception 'invalid continues'; end if;
  select max(created_at) into last_at from public.scores_continued where user_id = uid;
  if last_at is not null and last_at > now() - interval '8 seconds' then raise exception 'too fast'; end if;
  -- chaque score de partie continuée consomme UNE continuation réellement accordée (rewarded_continue, usage unique, 3 h)
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
end $function$;

create or replace function public.my_missions()
 RETURNS TABLE(code text, name text, goal integer, progress integer, reward_bc integer, reward_xp integer, claimed boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with today as (select (now() at time zone 'Europe/Paris')::date as d)
  select m.code, m.name, m.goal,
    least(m.goal, case m.kind
      when 'games' then (select count(*)::int from public.scores s, today t
                          where s.user_id = auth.uid()
                            and (s.created_at at time zone 'Europe/Paris')::date = t.d
                            and (m.game is null or s.game = m.game))
      else (select least(coalesce(max(s.score), 0), 2147483647)::int from public.scores s, today t
             where s.user_id = auth.uid()
               and (s.created_at at time zone 'Europe/Paris')::date = t.d
               and (m.game is null or s.game = m.game))
    end) as progress,
    m.reward_bc, m.reward_xp,
    exists (select 1 from public.mission_claims c, today t
             where c.user_id = auth.uid() and c.mission_code = m.code and c.day = t.d) as claimed
  from public.missions m
  where auth.uid() is not null
  order by m.sort;
$function$;

create or replace function public.leaderboard(p_game text, p_country text DEFAULT NULL::text, p_limit integer DEFAULT 50)
 RETURNS TABLE(rang bigint, pseudo text, score bigint, moi boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select
    rank() over (order by b.score desc) as rang,
    p.pseudo,
    b.score,
    (b.user_id = auth.uid()) as moi
  from (
    select s.user_id, max(s.score) as score
    from public.scores s
    where s.game = p_game
    group by s.user_id
  ) b
  join public.profiles p on p.id = b.user_id
  where p_country is null or p.country = p_country
  order by b.score desc, p.pseudo
  limit least(greatest(coalesce(p_limit, 50), 1), 100);
$function$;

create or replace function public.leaderboard_friends(p_game text, p_limit integer DEFAULT 50)
 RETURNS TABLE(rang bigint, pseudo text, score bigint, moi boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with circle as (
    select auth.uid() as id
    union
    select case when f.user_a = auth.uid() then f.user_b else f.user_a end
    from public.friendships f
    where f.status = 'accepted' and auth.uid() in (f.user_a, f.user_b)
  ),
  best as (
    select s.user_id, max(s.score) as score
    from public.scores s join circle c on c.id = s.user_id
    where s.game = p_game
    group by s.user_id
  )
  select rank() over (order by b.score desc) as rang, p.pseudo, b.score, (b.user_id = auth.uid()) as moi
  from best b join public.profiles p on p.id = b.user_id
  where auth.uid() is not null
  order by b.score desc, p.pseudo
  limit least(greatest(coalesce(p_limit, 50), 1), 100);
$function$;

create or replace function public.leaderboard_season(p_game text, p_country text DEFAULT NULL::text, p_limit integer DEFAULT 50)
 RETURNS TABLE(rang bigint, pseudo text, score bigint, moi boolean)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  select rank() over (order by b.score desc) as rang, p.pseudo, b.score, (b.user_id = auth.uid()) as moi
  from (
    select s.user_id, max(s.score) as score
    from public.scores s
    where s.game = p_game
      and to_char(s.created_at at time zone 'Europe/Paris', 'YYYY-MM') = public.current_season()
    group by s.user_id
  ) b
  join public.profiles p on p.id = b.user_id
  where p_country is null or p.country = p_country
  order by b.score desc, p.pseudo
  limit least(greatest(coalesce(p_limit, 50), 1), 100);
$function$;

create or replace function public.my_standing(p_game text, p_country text DEFAULT NULL::text)
 RETURNS TABLE(rang bigint, score bigint)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with best as (
    select s.user_id, max(s.score) as score
    from public.scores s
    where s.game = p_game
    group by s.user_id
  ),
  ranked as (
    select b.user_id, b.score, rank() over (order by b.score desc) as rang
    from best b
    join public.profiles p on p.id = b.user_id
    where p_country is null or p.country = p_country
  )
  select r.rang, r.score from ranked r where r.user_id = auth.uid();
$function$;

-- Droits (identiques à avant : seuls les joueurs connectés envoient via les fonctions à ticket ; l'envoi direct reste fermé)
revoke all on function public.game_max_score(text), public.bc_for_score(text, bigint), public.score_plausible(text, bigint, numeric),
  public.submit_score(text, bigint) from public, anon, authenticated;
revoke all on function public.submit_score_v2(text, bigint, uuid), public.submit_continued_score(text, bigint, integer),
  public.leaderboard(text, text, integer), public.leaderboard_friends(text, integer), public.leaderboard_season(text, text, integer),
  public.my_standing(text, text) from public, anon, authenticated;
grant execute on function public.submit_score_v2(text, bigint, uuid), public.submit_continued_score(text, bigint, integer),
  public.leaderboard_friends(text, integer), public.my_standing(text, text) to authenticated;
grant execute on function public.leaderboard(text, text, integer), public.leaderboard_season(text, text, integer) to anon, authenticated;

do $$ begin
  if public.game_max_score('space') <> 9007199254740991 or public.game_max_score('snake') <> 429 or public.game_max_score('blocks') <> 50000
     or public.game_max_score('autre') <> 0
     or has_function_privilege('authenticated', 'public.submit_score(text,bigint)', 'execute')
     or not has_function_privilege('authenticated', 'public.submit_score_v2(text,bigint,uuid)', 'execute') then
    raise exception 'GARDE-FOU : limites ou droits inattendus. Rien n''a été appliqué.';
  end if;
end $$;

commit;
select 'Migration v25 appliquée (scores bigint, plafond Space = 2^53-1)' as resultat, public.game_max_score('space') as limite_technique_space;

-- BOYGAM v4 : ouvre le classement à Block Puzzle (et prépare Space Attack).
-- À lancer APRÈS schema.sql, schema_v2.sql et schema_v3.sql. Tu peux le relancer sans danger.
-- Seule la liste des jeux et leur score maximum plausible change.
create or replace function public.game_max_score(p_game text)
returns int language sql immutable as $$
  select case p_game
    when 'snake' then 429
    when 'blocks' then 50000
    when 'space' then 20000
    else 0
  end;
$$;
revoke all on function public.game_max_score(text) from public;

create or replace function public.submit_score(p_game text, p_score int)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  today date := (now() at time zone 'Europe/Paris')::date;
  max_allowed int;
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
  if p_score is null or p_score < 0 or p_score > max_allowed then raise exception 'invalid score'; end if;

  select max(created_at) into last_at from public.scores where user_id = uid;
  if last_at is not null and last_at > now() - interval '8 seconds' then raise exception 'too fast'; end if;

  insert into public.player_stats (user_id) values (uid) on conflict do nothing;
  insert into public.scores (user_id, game, score) values (uid, p_game, p_score);

  -- Les gains sont ramenés à une échelle commune pour que tous les jeux rapportent à peu près pareil.
  xp_gain := 5 + case p_game when 'blocks' then least(p_score / 40, 60) when 'space' then least(p_score / 20, 60) else p_score / 2 end;
  bc_gain := 1 + case p_game when 'blocks' then least(p_score / 200, 25) when 'space' then least(p_score / 100, 25) else p_score / 10 end;
  select coalesce(sum(delta), 0) into earned_today from public.bc_ledger
   where user_id = uid and reason = 'game' and (created_at at time zone 'Europe/Paris')::date = today;
  bc_gain := least(bc_gain, greatest(0, 150 - earned_today));

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
$$;
revoke all on function public.submit_score(text, int) from public;
grant execute on function public.submit_score(text, int) to authenticated;

-- Les badges « Snake » ne comptent que les scores de Snake (un gros score à un autre jeu ne les débloque pas).
create or replace function public.check_badges(p_uid uuid)
returns text[] language plpgsql security definer set search_path = public as $$
declare
  n_games int;
  best int;
  lvl int;
  strk int;
  fresh text[];
begin
  select count(*) into n_games from public.scores where user_id = p_uid;
  select coalesce(max(score), 0) into best from public.scores where user_id = p_uid and game = 'snake';
  select level into lvl from public.player_stats where user_id = p_uid;
  select coalesce(max(streak), 0) into strk from public.login_streaks where user_id = p_uid;

  with ins as (
    insert into public.user_badges (user_id, badge_code)
    select p_uid, b.code from public.badges b
    where (b.code = 'first_game' and n_games >= 1)
       or (b.code = 'games_10' and n_games >= 10)
       or (b.code = 'games_100' and n_games >= 100)
       or (b.code = 'score_25' and best >= 25)
       or (b.code = 'score_100' and best >= 100)
       or (b.code = 'score_250' and best >= 250)
       or (b.code = 'level_5' and lvl >= 5)
       or (b.code = 'level_10' and lvl >= 10)
       or (b.code = 'streak_7' and strk >= 7)
    on conflict do nothing
    returning badge_code
  )
  select coalesce(array_agg(badge_code), '{}') into fresh from ins;
  return fresh;
end;
$$;
revoke all on function public.check_badges(uuid) from public;

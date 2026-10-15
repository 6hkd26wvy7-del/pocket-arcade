-- BOYGAMES — MIGRATION v11 : réglages de l'économie BOYCOINS administrables
-- À lancer APRÈS la v10. Tout-ou-rien, relançable. NE CHANGE AUCUN MONTANT : les réglages créés reprennent
-- exactement les valeurs actuelles (gains par partie, plafond quotidien, bonus de connexion, saison).
-- Les prix de la boutique et les récompenses des missions sont déjà dans des tables (shop_items, missions) :
-- ils deviennent modifiables par l'équipe via des fonctions contrôlées. Chaque changement est journalisé.
-- Aucun BC déjà acquis n'est touché.
begin;

do $$ begin
  if to_regprocedure('public.bb_replay2(bigint,jsonb,boolean,integer)') is null then
    raise exception 'PRE-CONTROLE : la migration v10 doit être lancée AVANT celle-ci. Rien n''a été modifié.';
  end if;
end $$;

do $$
begin
  perform set_config('boygames.mig_tx', txid_current()::text, true);
  perform set_config('boygames.mig_before', (jsonb_build_object(
    'profiles', (select count(*) from public.profiles), 'scores', (select count(*) from public.scores),
    'bc_ledger', (select count(*) from public.bc_ledger), 'user_items', (select count(*) from public.user_items),
    'shop', (select md5(string_agg(code || ':' || price, ',' order by code)) from public.shop_items),
    'missions', (select md5(string_agg(code || ':' || reward_bc || ':' || reward_xp, ',' order by code)) from public.missions),
    'sum_bc', (select coalesce(sum(bc), 0) from public.player_stats), 'sum_xp', (select coalesce(sum(xp), 0) from public.player_stats)))::text, true);
end $$;
do $$
begin
  if coalesce(current_setting('boygames.mig_tx', true), '') <> txid_current()::text
     or coalesce(current_setting('boygames.mig_before', true), '') = '' then
    raise exception 'EXECUTION EN PLUSIEURS MORCEAUX : ce script doit etre lance en entier, d''un seul bloc. Rien n''a ete modifie.';
  end if;
end $$;

-- ============ 1. Réglages ============
create table if not exists public.economy_settings (
  key text primary key,
  value jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);
alter table public.economy_settings enable row level security;          -- lecture uniquement par fonctions
revoke all on public.economy_settings from anon, authenticated;

create table if not exists public.economy_log (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  by_user uuid references auth.users(id) on delete set null,
  what text not null,
  old_value jsonb,
  new_value jsonb
);
alter table public.economy_log enable row level security;
revoke all on public.economy_log from anon, authenticated;

-- valeurs ACTUELLES (rien ne change tant que l'équipe ne les modifie pas)
insert into public.economy_settings (key, value) values
  ('game_bc', '{"snake": {"div": 10, "cap": null}, "blocks": {"div": 200, "cap": 25}, "space": {"div": 100, "cap": 25}, "boyblocks": {"div": 400, "cap": 25}}'),
  ('game_bc_daily_cap', '150'),
  ('daily_streak', '[10, 15, 20, 25, 30, 40, 100]'),
  ('season_rewards', '{"rank1": 500, "rank3": 300, "rank10": 150, "other": 30}')
on conflict (key) do nothing;

create or replace function public.econ(p_key text) returns jsonb language sql stable security definer set search_path = public as $$
  select value from public.economy_settings where key = p_key;
$$;

-- BC gagnés pour une partie : 1 + score / div, plafonné à cap (cap null = pas de plafond par partie)
create or replace function public.bc_for_score(p_game text, p_score int) returns int language plpgsql stable security definer set search_path = public as $$
declare g jsonb := public.econ('game_bc') -> p_game; v int;
begin
  if g is null then return 1; end if;
  v := p_score / greatest(1, (g ->> 'div')::int);
  if g ->> 'cap' is not null then v := least(v, (g ->> 'cap')::int); end if;
  return 1 + greatest(0, v);
end $$;

create or replace function public.bc_daily_cap() returns int language sql stable security definer set search_path = public as $$
  select coalesce((public.econ('game_bc_daily_cap'))::text::int, 150);
$$;

-- ============ 2. Fonctions de récompense : mêmes règles, montants lus dans les réglages ============
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
$$;

create or replace function public.bb_award(p_uid uuid, p_score int) returns jsonb language plpgsql security definer set search_path = public as $$
declare today date := (now() at time zone 'Europe/Paris')::date; xp_gain int; bc_gain int; earned_today int; before_level int; after_level int; badges text[];
begin
  insert into public.player_stats (user_id) values (p_uid) on conflict do nothing;
  insert into public.scores (user_id, game, score) values (p_uid, 'boyblocks', p_score);
  xp_gain := 5 + least(p_score / 80, 60);
  bc_gain := public.bc_for_score('boyblocks', p_score);
  select coalesce(sum(delta), 0) into earned_today from public.bc_ledger
   where user_id = p_uid and reason = 'game' and (created_at at time zone 'Europe/Paris')::date = today;
  bc_gain := least(bc_gain, greatest(0, public.bc_daily_cap() - earned_today));
  select level into before_level from public.player_stats where user_id = p_uid;
  perform public.add_xp(p_uid, xp_gain);
  if bc_gain > 0 then perform public.add_bc(p_uid, bc_gain, 'game'); end if;
  select level into after_level from public.player_stats where user_id = p_uid;
  badges := public.check_badges(p_uid);
  return jsonb_build_object('xp', xp_gain, 'bc', bc_gain, 'level', after_level, 'level_up', after_level > before_level, 'new_badges', to_jsonb(badges));
end $$;

create or replace function public.claim_daily()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  today date := (now() at time zone 'Europe/Paris')::date;
  st public.login_streaks;
  new_streak int;
  day_no int;
  reward int;
  rewards jsonb := coalesce(public.econ('daily_streak'), '[10, 15, 20, 25, 30, 40, 100]');
  badges text[];
begin
  perform public.guard_action(uid);
  if not exists (select 1 from public.player_stats where user_id = uid) then raise exception 'no profile'; end if;

  insert into public.login_streaks (user_id) values (uid) on conflict do nothing;
  select * into st from public.login_streaks where user_id = uid for update;

  if st.last_claim = today then raise exception 'already claimed'; end if;
  if st.last_claim = today - 1 then new_streak := st.streak + 1; else new_streak := 1; end if;

  day_no := ((new_streak - 1) % 7) + 1;
  reward := (rewards ->> (day_no - 1))::int;

  update public.login_streaks set last_claim = today, streak = new_streak where user_id = uid;
  perform public.add_bc(uid, reward, 'daily');
  badges := public.check_badges(uid);
  return jsonb_build_object('day', day_no, 'streak', new_streak, 'bc', reward, 'new_badges', to_jsonb(badges));
end;
$$;

create or replace function public.season_reward(p_rank int)
returns int language plpgsql stable security definer set search_path = public as $$
declare s jsonb := coalesce(public.econ('season_rewards'), '{"rank1": 500, "rank3": 300, "rank10": 150, "other": 30}');
begin
  return case when p_rank = 1 then (s ->> 'rank1')::int when p_rank <= 3 then (s ->> 'rank3')::int
              when p_rank <= 10 then (s ->> 'rank10')::int else (s ->> 'other')::int end;
end $$;

-- Ce que le site peut afficher (bonus de connexion) : lecture seule, joueurs connectés.
create or replace function public.economy_public() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object('daily_streak', public.econ('daily_streak'), 'game_bc_daily_cap', public.econ('game_bc_daily_cap'));
$$;

-- ============ 3. Administration (fondateur / admin uniquement), avec bornes et journal ============
create or replace function public.staff_economy() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  return jsonb_build_object(
    'settings', (select jsonb_object_agg(key, value) from public.economy_settings),
    'shop', (select jsonb_agg(jsonb_build_object('code', code, 'name', name, 'kind', kind, 'price', price) order by sort) from public.shop_items),
    'missions', (select jsonb_agg(jsonb_build_object('code', code, 'name', name, 'bc', reward_bc, 'xp', reward_xp) order by sort) from public.missions),
    'log', (select coalesce(jsonb_agg(jsonb_build_object('at', l.at, 'by', public.pseudo_of(l.by_user), 'what', l.what, 'old', l.old_value, 'new', l.new_value) order by l.id desc), '[]'::jsonb)
              from (select * from public.economy_log order by id desc limit 30) l));
end $$;

create or replace function public.staff_economy_set(p_key text, p_value jsonb) returns void language plpgsql security definer set search_path = public as $$
declare old jsonb; k text; v jsonb; i int;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  select value into old from public.economy_settings where key = p_key;
  if not found then raise exception 'unknown setting'; end if;
  -- bornes : évitent une faute de frappe qui distribuerait des milliers de BC
  if p_key = 'game_bc' then
    if jsonb_typeof(p_value) <> 'object' then raise exception 'invalid value'; end if;
    for k, v in select * from jsonb_each(p_value) loop
      if k not in ('snake', 'blocks', 'space', 'boyblocks') then raise exception 'invalid game'; end if;
      if (v ->> 'div') is null or (v ->> 'div')::int not between 1 and 100000 then raise exception 'invalid div'; end if;
      if (v ->> 'cap') is not null and (v ->> 'cap')::int not between 0 and 100 then raise exception 'invalid cap'; end if;
    end loop;
  elsif p_key = 'game_bc_daily_cap' then
    if jsonb_typeof(p_value) <> 'number' or p_value::text::int not between 0 and 1000 then raise exception 'invalid value'; end if;
  elsif p_key = 'daily_streak' then
    if jsonb_typeof(p_value) <> 'array' or jsonb_array_length(p_value) <> 7 then raise exception 'invalid value'; end if;
    for i in 0 .. 6 loop
      if jsonb_typeof(p_value -> i) <> 'number' or (p_value ->> i)::int not between 0 and 1000 then raise exception 'invalid value'; end if;
    end loop;
  elsif p_key = 'season_rewards' then
    if jsonb_typeof(p_value) <> 'object' then raise exception 'invalid value'; end if;
    foreach k in array array['rank1', 'rank3', 'rank10', 'other'] loop
      if (p_value ->> k) is null or (p_value ->> k)::int not between 0 and 10000 then raise exception 'invalid value'; end if;
    end loop;
  end if;
  update public.economy_settings set value = p_value, updated_at = now(), updated_by = auth.uid() where key = p_key;
  insert into public.economy_log (by_user, what, old_value, new_value) values (auth.uid(), 'setting:' || p_key, old, p_value);
end $$;

-- Prix d'un objet de la boutique : les objets déjà achetés restent acquis (aucun remboursement, aucun retrait).
create or replace function public.staff_set_price(p_code text, p_price int) returns void language plpgsql security definer set search_path = public as $$
declare old int;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  if p_price is null or p_price not between 0 and 100000 then raise exception 'invalid price'; end if;
  select price into old from public.shop_items where code = p_code;
  if not found then raise exception 'unknown item'; end if;
  update public.shop_items set price = p_price where code = p_code;
  insert into public.economy_log (by_user, what, old_value, new_value) values (auth.uid(), 'price:' || p_code, to_jsonb(old), to_jsonb(p_price));
end $$;

create or replace function public.staff_set_mission_reward(p_code text, p_bc int, p_xp int) returns void language plpgsql security definer set search_path = public as $$
declare m public.missions;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  if p_bc is null or p_bc not between 0 and 1000 or p_xp is null or p_xp not between 0 and 1000 then raise exception 'invalid reward'; end if;
  select * into m from public.missions where code = p_code;
  if not found then raise exception 'unknown mission'; end if;
  update public.missions set reward_bc = p_bc, reward_xp = p_xp where code = p_code;
  insert into public.economy_log (by_user, what, old_value, new_value)
  values (auth.uid(), 'mission:' || p_code, jsonb_build_object('bc', m.reward_bc, 'xp', m.reward_xp), jsonb_build_object('bc', p_bc, 'xp', p_xp));
end $$;

-- ============ 4. Droits ============
revoke all on function public.econ(text), public.bc_for_score(text, int), public.bc_daily_cap(),
  public.season_reward(int), public.bb_award(uuid, int) from public, anon, authenticated;
revoke all on function public.submit_score(text, int), public.claim_daily(), public.economy_public(),
  public.staff_economy(), public.staff_economy_set(text, jsonb), public.staff_set_price(text, int),
  public.staff_set_mission_reward(text, int, int) from public, anon;
grant execute on function public.submit_score(text, int), public.claim_daily(), public.economy_public(),
  public.staff_economy(), public.staff_economy_set(text, jsonb), public.staff_set_price(text, int),
  public.staff_set_mission_reward(text, int, int) to authenticated;

-- ============ 5. Contrôles ============
do $$
declare b jsonb; a jsonb := jsonb_build_object(
    'profiles', (select count(*) from public.profiles), 'scores', (select count(*) from public.scores),
    'bc_ledger', (select count(*) from public.bc_ledger), 'user_items', (select count(*) from public.user_items),
    'shop', (select md5(string_agg(code || ':' || price, ',' order by code)) from public.shop_items),
    'missions', (select md5(string_agg(code || ':' || reward_bc || ':' || reward_xp, ',' order by code)) from public.missions),
    'sum_bc', (select coalesce(sum(bc), 0) from public.player_stats), 'sum_xp', (select coalesce(sum(xp), 0) from public.player_stats));
begin
  if coalesce(current_setting('boygames.mig_tx', true), '') <> txid_current()::text then
    raise exception 'EXECUTION EN PLUSIEURS MORCEAUX : relancer le script en entier, d''un seul bloc.';
  end if;
  b := current_setting('boygames.mig_before')::jsonb;
  if a is distinct from b then
    raise exception 'GARDE-FOU : des donnees existantes auraient change (% -> %). Rien n''a ete applique.', b, a;
  end if;
  -- les réglages par défaut donnent exactement les montants d'avant
  if public.bc_for_score('snake', 37) <> 4 or public.bc_for_score('blocks', 14100) <> 26 or public.bc_for_score('space', 1234) <> 13
     or public.bc_for_score('boyblocks', 99999) <> 26 or public.bc_daily_cap() <> 150 or public.season_reward(1) <> 500
     or public.season_reward(7) <> 150 or public.season_reward(50) <> 30 then
    raise exception 'GARDE-FOU : les montants ne correspondent plus aux montants actuels. Rien n''a ete applique.';
  end if;
  if has_function_privilege('authenticated', 'public.econ(text)', 'execute')
     or has_function_privilege('authenticated', 'public.bc_for_score(text,integer)', 'execute')
     or has_function_privilege('anon', 'public.staff_economy()', 'execute')
     or has_function_privilege('anon', 'public.economy_public()', 'execute')
     or not has_function_privilege('authenticated', 'public.submit_score(text,integer)', 'execute')
     or has_table_privilege('authenticated', 'public.economy_settings', 'select') then
    raise exception 'GARDE-FOU DROITS : permissions inattendues. Rien n''a été appliqué.';
  end if;
end $$;

commit;

select 'Migration v11 appliquée (aucun montant modifié)' as resultat,
  (select jsonb_object_agg(key, value) from public.economy_settings) as reglages;

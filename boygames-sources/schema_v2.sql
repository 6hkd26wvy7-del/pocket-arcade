-- BOYGAM v2 : XP, niveaux, BOYCOINS, badges, missions, récompense quotidienne, boutique.
-- À lancer APRÈS schema.sql, d'abord sur le projet de TEST.
-- Tu peux le relancer sans danger.
-- Règle d'or : le navigateur ne peut JAMAIS écrire directement dans ces tables.
-- Tout passe par des fonctions qui vérifient les règles côté serveur.

-- ============ 1. Stats du joueur (XP, niveau, BOYCOINS) ============
create table if not exists public.player_stats (
  user_id uuid primary key references auth.users(id) on delete cascade,
  xp int not null default 0 check (xp >= 0),
  level int not null default 1 check (level >= 1),
  bc int not null default 0 check (bc >= 0),
  created_at timestamptz not null default now()
);
alter table public.player_stats enable row level security;
drop policy if exists "je lis mes stats" on public.player_stats;
create policy "je lis mes stats" on public.player_stats for select using (auth.uid() = user_id);

-- Journal de toutes les opérations de BOYCOINS (traçabilité, anti-triche).
create table if not exists public.bc_ledger (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  delta int not null,
  reason text not null,
  created_at timestamptz not null default now()
);
create index if not exists bc_ledger_user_day on public.bc_ledger (user_id, created_at);
alter table public.bc_ledger enable row level security;
drop policy if exists "je lis mon journal" on public.bc_ledger;
create policy "je lis mon journal" on public.bc_ledger for select using (auth.uid() = user_id);

-- Une ligne de stats est créée automatiquement avec chaque profil.
create or replace function public.create_stats_for_profile()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.player_stats (user_id) values (new.id) on conflict do nothing;
  return new;
end;
$$;
drop trigger if exists profile_creates_stats on public.profiles;
create trigger profile_creates_stats after insert on public.profiles
  for each row execute function public.create_stats_for_profile();

-- Les comptes déjà existants reçoivent leur ligne de stats (sans rien retirer à personne).
insert into public.player_stats (user_id) select id from public.profiles on conflict do nothing;

-- ============ 2. Niveaux ============
-- Niveau 2 à 50 XP, niveau 3 à 200, niveau 4 à 450, niveau 5 à 800, niveau 10 à 4050...
create or replace function public.level_for_xp(p_xp int)
returns int language sql immutable as $$
  select floor(sqrt(greatest(p_xp, 0) / 50.0))::int + 1;
$$;

-- ============ 3. Fonctions internes (non appelables depuis le navigateur) ============
create or replace function public.add_bc(p_uid uuid, p_delta int, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.player_stats set bc = bc + p_delta where user_id = p_uid;
  if not found then raise exception 'no stats'; end if;
  insert into public.bc_ledger (user_id, delta, reason) values (p_uid, p_delta, p_reason);
end;
$$;
revoke all on function public.add_bc(uuid, int, text) from public;

create or replace function public.add_xp(p_uid uuid, p_xp int)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.player_stats
     set xp = xp + p_xp, level = public.level_for_xp(xp + p_xp)
   where user_id = p_uid;
  if not found then raise exception 'no stats'; end if;
end;
$$;
revoke all on function public.add_xp(uuid, int) from public;

-- ============ 4. Badges ============
create table if not exists public.badges (
  code text primary key,
  name text not null,
  description text not null,
  sort int not null default 0
);
alter table public.badges enable row level security;
drop policy if exists "badges lisibles par tous" on public.badges;
create policy "badges lisibles par tous" on public.badges for select using (true);

create table if not exists public.user_badges (
  user_id uuid not null references auth.users(id) on delete cascade,
  badge_code text not null references public.badges(code),
  earned_at timestamptz not null default now(),
  primary key (user_id, badge_code)
);
alter table public.user_badges enable row level security;
drop policy if exists "je lis mes badges" on public.user_badges;
create policy "je lis mes badges" on public.user_badges for select using (auth.uid() = user_id);

insert into public.badges (code, name, description, sort) values
  ('first_game', 'Premiers pas', 'Termine ta première partie.', 1),
  ('games_10', 'Habitué', 'Joue 10 parties.', 2),
  ('games_100', 'Accro', 'Joue 100 parties.', 3),
  ('score_25', 'Bon début', 'Fais 25 points ou plus à Snake.', 4),
  ('score_100', 'Serpent affamé', 'Fais 100 points ou plus à Snake.', 5),
  ('score_250', 'Maître serpent', 'Fais 250 points ou plus à Snake.', 6),
  ('level_5', 'Niveau 5', 'Atteins le niveau 5.', 7),
  ('level_10', 'Niveau 10', 'Atteins le niveau 10.', 8),
  ('streak_7', 'Fidèle', 'Récupère ta récompense 7 jours de suite.', 9)
on conflict (code) do update set name = excluded.name, description = excluded.description, sort = excluded.sort;

-- Débloque les badges mérités. Renvoie la liste des nouveaux badges.
create or replace function public.check_badges(p_uid uuid)
returns text[] language plpgsql security definer set search_path = public as $$
declare
  n_games int;
  best int;
  lvl int;
  strk int;
  fresh text[];
begin
  select count(*), coalesce(max(score), 0) into n_games, best from public.scores where user_id = p_uid;
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

-- ============ 5. Récompense quotidienne (7 jours) ============
create table if not exists public.login_streaks (
  user_id uuid primary key references auth.users(id) on delete cascade,
  last_claim date,
  streak int not null default 0
);
alter table public.login_streaks enable row level security;
drop policy if exists "je lis ma serie" on public.login_streaks;
create policy "je lis ma serie" on public.login_streaks for select using (auth.uid() = user_id);

create or replace function public.claim_daily()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  today date := (now() at time zone 'Europe/Paris')::date;
  st public.login_streaks;
  new_streak int;
  day_no int;
  reward int;
  rewards int[] := array[10, 15, 20, 25, 30, 40, 100];
  badges text[];
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if not exists (select 1 from public.player_stats where user_id = uid) then raise exception 'no profile'; end if;

  insert into public.login_streaks (user_id) values (uid) on conflict do nothing;
  select * into st from public.login_streaks where user_id = uid for update;

  if st.last_claim = today then raise exception 'already claimed'; end if;
  if st.last_claim = today - 1 then new_streak := st.streak + 1; else new_streak := 1; end if;

  day_no := ((new_streak - 1) % 7) + 1;
  reward := rewards[day_no];

  update public.login_streaks set last_claim = today, streak = new_streak where user_id = uid;
  perform public.add_bc(uid, reward, 'daily');
  badges := public.check_badges(uid);
  return jsonb_build_object('day', day_no, 'streak', new_streak, 'bc', reward, 'new_badges', to_jsonb(badges));
end;
$$;
revoke all on function public.claim_daily() from public;
grant execute on function public.claim_daily() to authenticated;

-- ============ 6. Missions du jour ============
create table if not exists public.missions (
  code text primary key,
  name text not null,
  kind text not null check (kind in ('games', 'best_score')),
  game text,
  goal int not null check (goal > 0),
  reward_bc int not null default 0,
  reward_xp int not null default 0,
  sort int not null default 0
);
alter table public.missions enable row level security;
drop policy if exists "missions lisibles par tous" on public.missions;
create policy "missions lisibles par tous" on public.missions for select using (true);

create table if not exists public.mission_claims (
  user_id uuid not null references auth.users(id) on delete cascade,
  mission_code text not null references public.missions(code),
  day date not null,
  primary key (user_id, mission_code, day)
);
alter table public.mission_claims enable row level security;
drop policy if exists "je lis mes missions reclamees" on public.mission_claims;
create policy "je lis mes missions reclamees" on public.mission_claims for select using (auth.uid() = user_id);

insert into public.missions (code, name, kind, game, goal, reward_bc, reward_xp, sort) values
  ('play_3', 'Joue 3 parties', 'games', null, 3, 20, 20, 1),
  ('snake_20', 'Fais 20 points à Snake', 'best_score', 'snake', 20, 25, 25, 2),
  ('play_10', 'Joue 10 parties', 'games', null, 10, 50, 50, 3)
on conflict (code) do update set name = excluded.name, kind = excluded.kind, game = excluded.game,
  goal = excluded.goal, reward_bc = excluded.reward_bc, reward_xp = excluded.reward_xp, sort = excluded.sort;

-- Progression calculée directement depuis les scores du jour (heure de Paris).
create or replace function public.my_missions()
returns table (code text, name text, goal int, progress int, reward_bc int, reward_xp int, claimed boolean)
language sql stable security definer set search_path = public as $$
  with today as (select (now() at time zone 'Europe/Paris')::date as d)
  select m.code, m.name, m.goal,
    least(m.goal, case m.kind
      when 'games' then (select count(*)::int from public.scores s, today t
                          where s.user_id = auth.uid()
                            and (s.created_at at time zone 'Europe/Paris')::date = t.d
                            and (m.game is null or s.game = m.game))
      else (select coalesce(max(s.score), 0)::int from public.scores s, today t
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
$$;
revoke all on function public.my_missions() from public;
grant execute on function public.my_missions() to authenticated;

create or replace function public.claim_mission(p_code text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  today date := (now() at time zone 'Europe/Paris')::date;
  m record;
  done boolean;
  badges text[];
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into m from public.missions mi where mi.code = p_code;
  if not found then raise exception 'unknown mission'; end if;

  select (mm.progress >= mm.goal) into done from public.my_missions() mm where mm.code = p_code;
  if not coalesce(done, false) then raise exception 'not done'; end if;

  begin
    insert into public.mission_claims (user_id, mission_code, day) values (uid, p_code, today);
  exception when unique_violation then
    raise exception 'already claimed';
  end;

  perform public.add_bc(uid, m.reward_bc, 'mission:' || p_code);
  perform public.add_xp(uid, m.reward_xp);
  badges := public.check_badges(uid);
  return jsonb_build_object('bc', m.reward_bc, 'xp', m.reward_xp, 'new_badges', to_jsonb(badges));
end;
$$;
revoke all on function public.claim_mission(text) from public;
grant execute on function public.claim_mission(text) to authenticated;

-- ============ 7. Boutique (objets cosmétiques) ============
create table if not exists public.shop_items (
  code text primary key,
  kind text not null check (kind in ('theme', 'skin', 'title')),
  name text not null,
  price int not null check (price >= 0),
  sort int not null default 0
);
alter table public.shop_items enable row level security;
drop policy if exists "boutique lisible par tous" on public.shop_items;
create policy "boutique lisible par tous" on public.shop_items for select using (true);

create table if not exists public.user_items (
  user_id uuid not null references auth.users(id) on delete cascade,
  item_code text not null references public.shop_items(code),
  equipped boolean not null default false,
  bought_at timestamptz not null default now(),
  primary key (user_id, item_code)
);
alter table public.user_items enable row level security;
drop policy if exists "je lis mes objets" on public.user_items;
create policy "je lis mes objets" on public.user_items for select using (auth.uid() = user_id);

insert into public.shop_items (code, kind, name, price, sort) values
  ('theme_night', 'theme', 'Thème Nuit', 100, 1),
  ('theme_sunset', 'theme', 'Thème Coucher de soleil', 150, 2),
  ('skin_neon', 'skin', 'Serpent Néon', 200, 3),
  ('skin_gold', 'skin', 'Serpent Doré', 400, 4),
  ('title_rookie', 'title', 'Titre : Recrue', 50, 5),
  ('title_legend', 'title', 'Titre : Légende', 500, 6)
on conflict (code) do update set kind = excluded.kind, name = excluded.name, price = excluded.price, sort = excluded.sort;

create or replace function public.buy_item(p_code text)
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  item public.shop_items;
  paid int;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into item from public.shop_items where code = p_code;
  if not found then raise exception 'unknown item'; end if;
  if exists (select 1 from public.user_items where user_id = uid and item_code = p_code) then
    raise exception 'already owned';
  end if;

  update public.player_stats set bc = bc - item.price where user_id = uid and bc >= item.price;
  if not found then raise exception 'not enough coins'; end if;

  insert into public.bc_ledger (user_id, delta, reason) values (uid, -item.price, 'shop:' || p_code);
  insert into public.user_items (user_id, item_code) values (uid, p_code);
end;
$$;
revoke all on function public.buy_item(text) from public;
grant execute on function public.buy_item(text) to authenticated;

create or replace function public.equip_item(p_code text, p_on boolean default true)
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  k text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select s.kind into k from public.shop_items s
    join public.user_items u on u.item_code = s.code and u.user_id = uid
   where s.code = p_code;
  if k is null then raise exception 'not owned'; end if;

  if p_on then
    update public.user_items u set equipped = false
      from public.shop_items s
     where u.item_code = s.code and u.user_id = uid and s.kind = k;
  end if;
  update public.user_items set equipped = p_on where user_id = uid and item_code = p_code;
end;
$$;
revoke all on function public.equip_item(text, boolean) from public;
grant execute on function public.equip_item(text, boolean) to authenticated;

-- ============ 8. Enregistrer un score : maintenant avec XP, BOYCOINS et badges ============
-- Gain par partie : 5 XP + 1 XP tous les 2 points. BOYCOINS : 1 + 1 tous les 10 points,
-- plafonnés à 150 BOYCOINS gagnés en jouant par jour (anti-triche).
drop function if exists public.submit_score(text, int);
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
  if uid is null then raise exception 'not authenticated'; end if;
  if not exists (select 1 from public.profiles where id = uid) then raise exception 'no profile'; end if;

  max_allowed := case p_game when 'snake' then 429 else 0 end;
  if max_allowed = 0 then raise exception 'unknown game'; end if;
  if p_score is null or p_score < 0 or p_score > max_allowed then raise exception 'invalid score'; end if;

  select max(created_at) into last_at from public.scores where user_id = uid;
  if last_at is not null and last_at > now() - interval '8 seconds' then raise exception 'too fast'; end if;

  insert into public.player_stats (user_id) values (uid) on conflict do nothing;
  insert into public.scores (user_id, game, score) values (uid, p_game, p_score);

  xp_gain := 5 + p_score / 2;
  bc_gain := 1 + p_score / 10;
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

-- ============ 9. Tout mon profil de joueur en un seul appel ============
create or replace function public.me()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'pseudo', p.pseudo,
    'country', p.country,
    'xp', s.xp,
    'level', s.level,
    'level_start_xp', 50 * (s.level - 1) * (s.level - 1),
    'next_level_xp', 50 * s.level * s.level,
    'bc', s.bc,
    'badges', coalesce((select jsonb_agg(ub.badge_code order by ub.earned_at) from public.user_badges ub where ub.user_id = p.id), '[]'::jsonb),
    'items', coalesce((select jsonb_agg(jsonb_build_object('code', ui.item_code, 'equipped', ui.equipped)) from public.user_items ui where ui.user_id = p.id), '[]'::jsonb),
    'streak', coalesce((select ls.streak from public.login_streaks ls where ls.user_id = p.id), 0),
    'daily_claimed_today', coalesce((select ls.last_claim = (now() at time zone 'Europe/Paris')::date from public.login_streaks ls where ls.user_id = p.id), false)
  )
  from public.profiles p
  join public.player_stats s on s.user_id = p.id
  where p.id = auth.uid();
$$;
revoke all on function public.me() from public;
grant execute on function public.me() to authenticated;

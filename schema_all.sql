-- Pocket Arcade : base de données (Supabase / PostgreSQL)
-- À coller en entier dans Supabase > SQL Editor, puis "Run".
-- Tu peux le relancer sans danger : il ne recrée pas ce qui existe déjà.

-- 1. Profils : un pseudo public et un pays par compte.
-- L'e-mail reste dans le système d'authentification de Supabase, jamais visible des autres joueurs.
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  pseudo text not null,
  country text not null default 'FR' check (country in ('FR', 'OTHER')),
  created_at timestamptz not null default now(),
  constraint pseudo_format check (pseudo ~ '^[A-Za-z0-9_-]{3,16}$')
);

create unique index if not exists profiles_pseudo_lower on public.profiles (lower(pseudo));

alter table public.profiles enable row level security;

drop policy if exists "profils lisibles par tous" on public.profiles;
create policy "profils lisibles par tous"
  on public.profiles for select using (true);

drop policy if exists "je cree mon profil" on public.profiles;
create policy "je cree mon profil"
  on public.profiles for insert with check (auth.uid() = id);

drop policy if exists "je modifie mon profil" on public.profiles;
create policy "je modifie mon profil"
  on public.profiles for update using (auth.uid() = id) with check (auth.uid() = id);

-- 2. Scores : une ligne par partie enregistrée, tous jeux confondus.
-- Personne ne peut écrire directement dans cette table : tout passe par submit_score().
create table if not exists public.scores (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  game text not null,
  score int not null check (score >= 0),
  created_at timestamptz not null default now()
);

create index if not exists scores_game_score on public.scores (game, score desc);
create index if not exists scores_user_game on public.scores (user_id, game);

alter table public.scores enable row level security;

drop policy if exists "je lis mes scores" on public.scores;
create policy "je lis mes scores"
  on public.scores for select using (auth.uid() = user_id);

-- 3. Enregistrer un score (vérifie la connexion, le profil, le jeu, le maximum possible et le rythme).
-- Pour ajouter un jeu plus tard : ajoute une ligne dans le "case" avec son score maximum.
drop function if exists public.submit_score(text, int);
create or replace function public.submit_score(p_game text, p_score int)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  max_allowed int;
  last_at timestamptz;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  if not exists (select 1 from public.profiles where id = uid) then
    raise exception 'no profile';
  end if;

  max_allowed := case p_game
    when 'snake' then 429
    else 0
  end;

  if max_allowed = 0 then
    raise exception 'unknown game';
  end if;
  if p_score is null or p_score < 0 or p_score > max_allowed then
    raise exception 'invalid score';
  end if;

  select max(created_at) into last_at from public.scores where user_id = uid;
  if last_at is not null and last_at > now() - interval '8 seconds' then
    raise exception 'too fast';
  end if;

  insert into public.scores (user_id, game, score) values (uid, p_game, p_score);
end;
$$;

revoke all on function public.submit_score(text, int) from public;
grant execute on function public.submit_score(text, int) to authenticated;

-- 4. Classement : meilleur score de chaque joueur pour un jeu.
-- p_country = null pour le monde entier, 'FR' pour la France.
create or replace function public.leaderboard(p_game text, p_country text default null, p_limit int default 50)
returns table (rang bigint, pseudo text, score int, moi boolean)
language sql
stable
security definer
set search_path = public
as $$
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
$$;

revoke all on function public.leaderboard(text, text, int) from public;
grant execute on function public.leaderboard(text, text, int) to anon, authenticated;

-- 5. Mon rang et mon meilleur score (même si je suis hors du top 50).
create or replace function public.my_standing(p_game text, p_country text default null)
returns table (rang bigint, score int)
language sql
stable
security definer
set search_path = public
as $$
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
$$;

revoke all on function public.my_standing(text, text) from public;
grant execute on function public.my_standing(text, text) to authenticated;

-- 6. Supprimer mon compte et toutes mes données (droit à l'effacement).
create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.delete_my_account() from public;
grant execute on function public.delete_my_account() to authenticated;
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
-- BOYGAM v3 : amis, messages, notifications, cadeaux, saison, actualités,
-- mode maintenance, modération, rôle fondateur / administration.
-- À lancer APRÈS schema.sql et schema_v2.sql, d'abord sur le projet de TEST.
-- Tu peux le relancer sans danger.
-- Même règle d'or : le navigateur n'écrit jamais directement, tout passe par des fonctions.

-- ============ 1. Rôles (fondateur, administrateur, modérateur) ============
-- Personne ne peut se donner un rôle depuis le site. Le fondateur est ajouté à la main
-- dans le SQL Editor (voir la fin de ce fichier).
create table if not exists public.user_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('founder', 'admin', 'moderator'))
);
alter table public.user_roles enable row level security;
drop policy if exists "je lis mon role" on public.user_roles;
create policy "je lis mon role" on public.user_roles for select using (auth.uid() = user_id);

create or replace function public.is_staff(p_uid uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.user_roles where user_id = p_uid);
$$;
revoke all on function public.is_staff(uuid) from public;

create or replace function public.is_admin(p_uid uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.user_roles where user_id = p_uid and role in ('founder', 'admin'));
$$;
revoke all on function public.is_admin(uuid) from public;

create or replace function public.my_role()
returns text language sql stable security definer set search_path = public as $$
  select role from public.user_roles where user_id = auth.uid();
$$;
revoke all on function public.my_role() from public;
grant execute on function public.my_role() to authenticated;

-- ============ 2. Bannissements et mode maintenance ============
create table if not exists public.bans (
  user_id uuid primary key references auth.users(id) on delete cascade,
  reason text not null default '',
  banned_at timestamptz not null default now(),
  until timestamptz
);
alter table public.bans enable row level security;
drop policy if exists "je vois mon bannissement" on public.bans;
create policy "je vois mon bannissement" on public.bans for select using (auth.uid() = user_id);

create or replace function public.is_banned(p_uid uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.bans where user_id = p_uid and (until is null or until > now()));
$$;
revoke all on function public.is_banned(uuid) from public;

create table if not exists public.app_settings (
  key text primary key,
  value jsonb not null
);
alter table public.app_settings enable row level security;
insert into public.app_settings (key, value) values ('maintenance', '{"on": false, "message": ""}')
  on conflict (key) do nothing;

create or replace function public.get_maintenance()
returns jsonb language sql stable security definer set search_path = public as $$
  select value from public.app_settings where key = 'maintenance';
$$;
revoke all on function public.get_maintenance() from public;
grant execute on function public.get_maintenance() to anon, authenticated;

-- Contrôle commun : bloque les joueurs bannis, et tout le monde sauf l'équipe pendant la maintenance.
create or replace function public.guard_action(p_uid uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_uid is null then raise exception 'not authenticated'; end if;
  if public.is_banned(p_uid) then raise exception 'banned'; end if;
  if coalesce((select (value ->> 'on')::boolean from public.app_settings where key = 'maintenance'), false)
     and not public.is_staff(p_uid) then
    raise exception 'maintenance';
  end if;
end;
$$;
revoke all on function public.guard_action(uuid) from public;

-- ============ 3. Notifications ============
create table if not exists public.notifications (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null,
  body text not null default '',
  read boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists notifications_user on public.notifications (user_id, read, created_at desc);
alter table public.notifications enable row level security;
drop policy if exists "je lis mes notifications" on public.notifications;
create policy "je lis mes notifications" on public.notifications for select using (auth.uid() = user_id);

create or replace function public.notify(p_uid uuid, p_kind text, p_body text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_kind = 'message' and exists (
    select 1 from public.notifications where user_id = p_uid and kind = 'message' and body = p_body and not read) then
    return;
  end if;
  insert into public.notifications (user_id, kind, body) values (p_uid, p_kind, p_body);
  delete from public.notifications where user_id = p_uid and id not in (
    select id from public.notifications where user_id = p_uid order by id desc limit 100);
end;
$$;
revoke all on function public.notify(uuid, text, text) from public;

create or replace function public.my_notifications(p_limit int default 30)
returns table (id bigint, kind text, body text, read boolean, created_at timestamptz)
language sql stable security definer set search_path = public as $$
  select n.id, n.kind, n.body, n.read, n.created_at
  from public.notifications n
  where n.user_id = auth.uid()
  order by n.id desc
  limit least(greatest(coalesce(p_limit, 30), 1), 100);
$$;
revoke all on function public.my_notifications(int) from public;
grant execute on function public.my_notifications(int) to authenticated;

create or replace function public.mark_notifications_read()
returns void language sql security definer set search_path = public as $$
  update public.notifications set read = true where user_id = auth.uid() and not read;
$$;
revoke all on function public.mark_notifications_read() from public;
grant execute on function public.mark_notifications_read() to authenticated;

-- ============ 4. Amis ============
create table if not exists public.friendships (
  user_a uuid not null references auth.users(id) on delete cascade,
  user_b uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  requested_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)
);
create index if not exists friendships_b on public.friendships (user_b);
alter table public.friendships enable row level security;
drop policy if exists "je vois mes amities" on public.friendships;
create policy "je vois mes amities" on public.friendships for select using (auth.uid() in (user_a, user_b));

create or replace function public.uid_of(p_pseudo text)
returns uuid language sql stable security definer set search_path = public as $$
  select id from public.profiles where lower(pseudo) = lower(trim(p_pseudo));
$$;
revoke all on function public.uid_of(text) from public;

create or replace function public.are_friends(p1 uuid, p2 uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.friendships
                  where user_a = least(p1, p2) and user_b = greatest(p1, p2) and status = 'accepted');
$$;
revoke all on function public.are_friends(uuid, uuid) from public;

create or replace function public.pseudo_of(p_uid uuid)
returns text language sql stable security definer set search_path = public as $$
  select pseudo from public.profiles where id = p_uid;
$$;
revoke all on function public.pseudo_of(uuid) from public;

create or replace function public.send_friend_request(p_pseudo text)
returns text language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  other uuid;
  fr public.friendships;
  pending_out int;
begin
  perform public.guard_action(uid);
  other := public.uid_of(p_pseudo);
  if other is null then raise exception 'unknown player'; end if;
  if other = uid then raise exception 'cannot add yourself'; end if;

  select * into fr from public.friendships where user_a = least(uid, other) and user_b = greatest(uid, other);
  if found then
    if fr.status = 'accepted' then raise exception 'already friends'; end if;
    if fr.requested_by = uid then raise exception 'already requested'; end if;
    update public.friendships set status = 'accepted' where user_a = fr.user_a and user_b = fr.user_b;
    perform public.notify(other, 'friend_accept', public.pseudo_of(uid));
    return 'accepted';
  end if;

  select count(*) into pending_out from public.friendships where requested_by = uid and status = 'pending';
  if pending_out >= 30 then raise exception 'too many requests'; end if;

  insert into public.friendships (user_a, user_b, requested_by) values (least(uid, other), greatest(uid, other), uid);
  perform public.notify(other, 'friend_request', public.pseudo_of(uid));
  return 'requested';
end;
$$;
revoke all on function public.send_friend_request(text) from public;
grant execute on function public.send_friend_request(text) to authenticated;

create or replace function public.respond_friend_request(p_pseudo text, p_accept boolean)
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  other uuid;
begin
  perform public.guard_action(uid);
  other := public.uid_of(p_pseudo);
  if other is null then raise exception 'unknown player'; end if;
  if not exists (select 1 from public.friendships
                  where user_a = least(uid, other) and user_b = greatest(uid, other)
                    and status = 'pending' and requested_by = other) then
    raise exception 'no request';
  end if;
  if p_accept then
    update public.friendships set status = 'accepted'
     where user_a = least(uid, other) and user_b = greatest(uid, other);
    perform public.notify(other, 'friend_accept', public.pseudo_of(uid));
  else
    delete from public.friendships where user_a = least(uid, other) and user_b = greatest(uid, other);
  end if;
end;
$$;
revoke all on function public.respond_friend_request(text, boolean) from public;
grant execute on function public.respond_friend_request(text, boolean) to authenticated;

create or replace function public.remove_friend(p_pseudo text)
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  other uuid;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  other := public.uid_of(p_pseudo);
  if other is null then raise exception 'unknown player'; end if;
  delete from public.friendships where user_a = least(uid, other) and user_b = greatest(uid, other);
end;
$$;
revoke all on function public.remove_friend(text) from public;
grant execute on function public.remove_friend(text) to authenticated;

create or replace function public.my_friends()
returns table (pseudo text, level int, relation text)
language sql stable security definer set search_path = public as $$
  select p.pseudo, coalesce(s.level, 1),
         case when f.status = 'accepted' then 'friend'
              when f.requested_by <> auth.uid() then 'incoming'
              else 'outgoing' end
  from public.friendships f
  join public.profiles p on p.id = case when f.user_a = auth.uid() then f.user_b else f.user_a end
  left join public.player_stats s on s.user_id = p.id
  where auth.uid() in (f.user_a, f.user_b)
  order by case when f.status = 'accepted' then 1 when f.requested_by <> auth.uid() then 0 else 2 end, p.pseudo;
$$;
revoke all on function public.my_friends() from public;
grant execute on function public.my_friends() to authenticated;

-- Classement entre amis (moi + mes amis acceptés).
create or replace function public.leaderboard_friends(p_game text, p_limit int default 50)
returns table (rang bigint, pseudo text, score int, moi boolean)
language sql stable security definer set search_path = public as $$
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
$$;
revoke all on function public.leaderboard_friends(text, int) from public;
grant execute on function public.leaderboard_friends(text, int) to authenticated;

-- ============ 5. Cadeaux de BOYCOINS entre amis ============
-- Limites anti-abus : amis uniquement, niveau 3 minimum pour offrir, 1 à 50 par cadeau, 100 par jour.
create or replace function public.send_gift(p_pseudo text, p_amount int)
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  other uuid;
  today date := (now() at time zone 'Europe/Paris')::date;
  sent_today int;
  lvl int;
begin
  perform public.guard_action(uid);
  other := public.uid_of(p_pseudo);
  if other is null then raise exception 'unknown player'; end if;
  if other = uid then raise exception 'cannot gift yourself'; end if;
  if not public.are_friends(uid, other) then raise exception 'not friends'; end if;
  if p_amount is null or p_amount < 1 or p_amount > 50 then raise exception 'invalid amount'; end if;

  select level into lvl from public.player_stats where user_id = uid;
  if coalesce(lvl, 1) < 3 then raise exception 'level too low'; end if;

  select coalesce(-sum(delta), 0) into sent_today from public.bc_ledger
   where user_id = uid and reason = 'gift_out' and (created_at at time zone 'Europe/Paris')::date = today;
  if sent_today + p_amount > 100 then raise exception 'daily gift limit'; end if;

  update public.player_stats set bc = bc - p_amount where user_id = uid and bc >= p_amount;
  if not found then raise exception 'not enough coins'; end if;
  insert into public.bc_ledger (user_id, delta, reason) values (uid, -p_amount, 'gift_out');
  perform public.add_bc(other, p_amount, 'gift_in');
  perform public.notify(other, 'gift', public.pseudo_of(uid) || ' t''a offert ' || p_amount || ' BOYCOINS');
end;
$$;
revoke all on function public.send_gift(text, int) from public;
grant execute on function public.send_gift(text, int) to authenticated;

-- ============ 6. Messages privés (entre amis) avec filtre ============
create table if not exists public.banned_words (word text primary key);
alter table public.banned_words enable row level security;
insert into public.banned_words (word) values ('connard'), ('salope'), ('encule'), ('nazi'), ('pute'), ('pedophile')
  on conflict do nothing;

create table if not exists public.messages (
  id bigint generated always as identity primary key,
  from_id uuid not null references auth.users(id) on delete cascade,
  to_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 300),
  read boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists messages_pair on public.messages (to_id, from_id, id);
alter table public.messages enable row level security;
drop policy if exists "je lis mes messages" on public.messages;
create policy "je lis mes messages" on public.messages for select using (auth.uid() in (from_id, to_id));

create or replace function public.send_message(p_pseudo text, p_body text)
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  other uuid;
  txt text := trim(coalesce(p_body, ''));
begin
  perform public.guard_action(uid);
  other := public.uid_of(p_pseudo);
  if other is null then raise exception 'unknown player'; end if;
  if not public.are_friends(uid, other) then raise exception 'not friends'; end if;
  if char_length(txt) < 1 or char_length(txt) > 300 then raise exception 'invalid message'; end if;
  if (select count(*) from public.messages where from_id = uid and created_at > now() - interval '1 minute') >= 20 then
    raise exception 'too fast';
  end if;
  if exists (select 1 from public.banned_words w
              where translate(lower(txt), 'éèêëàâîïôùûç', 'eeeeaaiiouuc') ~ ('\m' || w.word || '\M')) then
    raise exception 'message refused';
  end if;
  insert into public.messages (from_id, to_id, body) values (uid, other, txt);
  perform public.notify(other, 'message', public.pseudo_of(uid));
end;
$$;
revoke all on function public.send_message(text, text) from public;
grant execute on function public.send_message(text, text) to authenticated;

create or replace function public.conversation(p_pseudo text, p_limit int default 50)
returns table (id bigint, mine boolean, body text, created_at timestamptz)
language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  other uuid;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  other := public.uid_of(p_pseudo);
  if other is null or not public.are_friends(uid, other) then raise exception 'not friends'; end if;
  update public.messages m set read = true where m.to_id = uid and m.from_id = other and not m.read;
  update public.notifications n set read = true
   where n.user_id = uid and n.kind = 'message' and n.body = public.pseudo_of(other) and not n.read;
  return query
    select x.id, (x.from_id = uid), x.body, x.created_at
    from (select m.* from public.messages m
           where (m.from_id = uid and m.to_id = other) or (m.from_id = other and m.to_id = uid)
           order by m.id desc
           limit least(greatest(coalesce(p_limit, 50), 1), 100)) x
    order by x.id;
end;
$$;
revoke all on function public.conversation(text, int) from public;
grant execute on function public.conversation(text, int) to authenticated;

-- ============ 7. Signalements et modération ============
create table if not exists public.reports (
  id bigint generated always as identity primary key,
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reported_id uuid not null references auth.users(id) on delete cascade,
  reason text not null check (char_length(reason) between 1 and 300),
  status text not null default 'open' check (status in ('open', 'done')),
  created_at timestamptz not null default now()
);
alter table public.reports enable row level security;

create or replace function public.report_user(p_pseudo text, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  other uuid;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  other := public.uid_of(p_pseudo);
  if other is null or other = uid then raise exception 'unknown player'; end if;
  if char_length(trim(coalesce(p_reason, ''))) < 1 then raise exception 'reason required'; end if;
  if (select count(*) from public.reports where reporter_id = uid and created_at > now() - interval '1 day') >= 10 then
    raise exception 'too many reports';
  end if;
  insert into public.reports (reporter_id, reported_id, reason) values (uid, other, left(trim(p_reason), 300));
end;
$$;
revoke all on function public.report_user(text, text) from public;
grant execute on function public.report_user(text, text) to authenticated;

create or replace function public.staff_reports()
returns table (id bigint, reporter text, reported text, reason text, created_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff() then raise exception 'forbidden'; end if;
  return query
    select r.id, public.pseudo_of(r.reporter_id), public.pseudo_of(r.reported_id), r.reason, r.created_at
    from public.reports r where r.status = 'open' order by r.id;
end;
$$;
revoke all on function public.staff_reports() from public;
grant execute on function public.staff_reports() to authenticated;

create or replace function public.staff_resolve_report(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff() then raise exception 'forbidden'; end if;
  update public.reports set status = 'done' where id = p_id;
end;
$$;
revoke all on function public.staff_resolve_report(bigint) from public;
grant execute on function public.staff_resolve_report(bigint) to authenticated;

create or replace function public.staff_ban(p_pseudo text, p_reason text, p_days int default null)
returns void language plpgsql security definer set search_path = public as $$
declare
  other uuid := public.uid_of(p_pseudo);
begin
  if not public.is_staff() then raise exception 'forbidden'; end if;
  if other is null then raise exception 'unknown player'; end if;
  if public.is_staff(other) then raise exception 'cannot ban staff'; end if;
  insert into public.bans (user_id, reason, until)
  values (other, left(coalesce(p_reason, ''), 300), case when p_days is null then null else now() + make_interval(days => p_days) end)
  on conflict (user_id) do update set reason = excluded.reason, until = excluded.until, banned_at = now();
end;
$$;
revoke all on function public.staff_ban(text, text, int) from public;
grant execute on function public.staff_ban(text, text, int) to authenticated;

create or replace function public.staff_unban(p_pseudo text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_staff() then raise exception 'forbidden'; end if;
  delete from public.bans where user_id = public.uid_of(p_pseudo);
end;
$$;
revoke all on function public.staff_unban(text) from public;
grant execute on function public.staff_unban(text) to authenticated;

-- ============ 8. Actualités ============
create table if not exists public.news (
  id bigint generated always as identity primary key,
  title text not null check (char_length(title) between 1 and 80),
  body text not null check (char_length(body) between 1 and 600),
  created_at timestamptz not null default now()
);
alter table public.news enable row level security;
drop policy if exists "actualites lisibles par tous" on public.news;
create policy "actualites lisibles par tous" on public.news for select using (true);

create or replace function public.staff_post_news(p_title text, p_body text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  insert into public.news (title, body) values (trim(p_title), trim(p_body));
end;
$$;
revoke all on function public.staff_post_news(text, text) from public;
grant execute on function public.staff_post_news(text, text) to authenticated;

create or replace function public.staff_delete_news(p_id bigint)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  delete from public.news where id = p_id;
end;
$$;
revoke all on function public.staff_delete_news(bigint) from public;
grant execute on function public.staff_delete_news(bigint) to authenticated;

create or replace function public.staff_set_maintenance(p_on boolean, p_message text default '')
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  update public.app_settings set value = jsonb_build_object('on', coalesce(p_on, false), 'message', left(coalesce(p_message, ''), 200))
   where key = 'maintenance';
end;
$$;
revoke all on function public.staff_set_maintenance(boolean, text) from public;
grant execute on function public.staff_set_maintenance(boolean, text) to authenticated;

-- ============ 9. Tableau de bord administrateur ============
create or replace function public.staff_stats()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  today date := (now() at time zone 'Europe/Paris')::date;
begin
  if not public.is_staff() then raise exception 'forbidden'; end if;
  return jsonb_build_object(
    'players', (select count(*) from public.profiles),
    'new_today', (select count(*) from public.profiles where (created_at at time zone 'Europe/Paris')::date = today),
    'games_today', (select count(*) from public.scores where (created_at at time zone 'Europe/Paris')::date = today),
    'bc_in_circulation', (select coalesce(sum(bc), 0) from public.player_stats),
    'open_reports', (select count(*) from public.reports where status = 'open'),
    'banned', (select count(*) from public.bans where until is null or until > now()));
end;
$$;
revoke all on function public.staff_stats() from public;
grant execute on function public.staff_stats() to authenticated;

-- ============ 10. Saison mensuelle ============
-- La saison = le mois en cours (heure de Paris). Classement = meilleur score du mois.
create or replace function public.current_season()
returns text language sql stable as $$
  select to_char(now() at time zone 'Europe/Paris', 'YYYY-MM');
$$;
grant execute on function public.current_season() to anon, authenticated;

create or replace function public.leaderboard_season(p_game text, p_country text default null, p_limit int default 50)
returns table (rang bigint, pseudo text, score int, moi boolean)
language sql stable security definer set search_path = public as $$
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
$$;
revoke all on function public.leaderboard_season(text, text, int) from public;
grant execute on function public.leaderboard_season(text, text, int) to anon, authenticated;

-- ============ 11. Les règles de v2 tiennent compte des bannissements et de la maintenance ============
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
  perform public.guard_action(uid);
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

-- Récompense du jour, missions et boutique : mêmes contrôles (bannissement, maintenance).
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
  perform public.guard_action(uid);
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

create or replace function public.claim_mission(p_code text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  today date := (now() at time zone 'Europe/Paris')::date;
  m record;
  done boolean;
  badges text[];
begin
  perform public.guard_action(uid);
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

create or replace function public.buy_item(p_code text)
returns void language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  item public.shop_items;
  paid int;
begin
  perform public.guard_action(uid);
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

-- ============ 12. Donner le rôle de FONDATEUR (à faire UNE fois, à la main) ============
-- Remplace l'identifiant ci-dessous par celui de ton compte (Authentication > Users),
-- enlève les deux tirets du début de la ligne, puis lance seulement cette ligne :
-- insert into public.user_roles (user_id, role) values ('REMPLACE-PAR-TON-IDENTIFIANT', 'founder') on conflict (user_id) do update set role = 'founder';
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
-- BOYGAM v5 : récompenses de fin de saison, bêta privée, gestion des rôles, sauvegarde exportable.
-- À lancer APRÈS schema.sql, v2, v3 et v4. Tu peux le relancer sans danger.

-- ============ 1. Récompenses de fin de saison ============
-- Le mois précédent est terminé : chaque joueur classé reçoit une récompense selon son rang, par jeu.
-- Rang 1 : 500 BC, rangs 2-3 : 300 BC, rangs 4-10 : 150 BC, les autres classés : 30 BC.
create table if not exists public.season_claims (
  user_id uuid not null references auth.users(id) on delete cascade,
  season text not null,
  game text not null,
  rank int not null,
  bc int not null,
  claimed_at timestamptz not null default now(),
  primary key (user_id, season, game)
);
alter table public.season_claims enable row level security;
drop policy if exists "je lis mes recompenses de saison" on public.season_claims;
create policy "je lis mes recompenses de saison" on public.season_claims for select using (auth.uid() = user_id);

create or replace function public.previous_season()
returns text language sql stable as $$
  select to_char((now() at time zone 'Europe/Paris') - interval '1 month', 'YYYY-MM');
$$;
grant execute on function public.previous_season() to anon, authenticated;

create or replace function public.season_reward(p_rank int)
returns int language sql immutable as $$
  select case when p_rank = 1 then 500 when p_rank <= 3 then 300 when p_rank <= 10 then 150 else 30 end;
$$;
revoke all on function public.season_reward(int) from public;

-- Mes récompenses de la saison passée (déjà récupérées ou non).
create or replace function public.my_season_rewards()
returns table (game text, season text, rang bigint, reward int, claimed boolean)
language sql stable security definer set search_path = public as $$
  with best as (
    select s.game, s.user_id, max(s.score) as score
    from public.scores s
    where to_char(s.created_at at time zone 'Europe/Paris', 'YYYY-MM') = public.previous_season()
    group by s.game, s.user_id
  ),
  ranked as (
    select b.game, b.user_id, rank() over (partition by b.game order by b.score desc) as rnk from best b
  )
  select r.game, public.previous_season(), r.rnk, public.season_reward(r.rnk::int),
         exists (select 1 from public.season_claims c
                  where c.user_id = r.user_id and c.season = public.previous_season() and c.game = r.game)
  from ranked r
  where r.user_id = auth.uid()
  order by r.game;
$$;
revoke all on function public.my_season_rewards() from public;
grant execute on function public.my_season_rewards() to authenticated;

create or replace function public.claim_season_rewards()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  uid uuid := auth.uid();
  r record;
  total int := 0;
begin
  perform public.guard_action(uid);
  for r in select * from public.my_season_rewards() mr where not mr.claimed loop
    begin
      insert into public.season_claims (user_id, season, game, rank, bc) values (uid, r.season, r.game, r.rang::int, r.reward);
    exception when unique_violation then
      continue; -- déjà récupérée (double clic)
    end;
    perform public.add_bc(uid, r.reward, 'season:' || r.season || ':' || r.game);
    total := total + r.reward;
  end loop;
  return jsonb_build_object('bc', total);
end;
$$;
revoke all on function public.claim_season_rewards() from public;
grant execute on function public.claim_season_rewards() to authenticated;

-- ============ 2. Bêta privée ============
-- Quand elle est activée, seuls les testeurs ajoutés (et l'équipe) peuvent jouer en ligne, envoyer des scores, etc.
insert into public.app_settings (key, value) values ('beta', '{"on": false}') on conflict (key) do nothing;

create table if not exists public.beta_members (
  user_id uuid primary key references auth.users(id) on delete cascade,
  added_at timestamptz not null default now()
);
alter table public.beta_members enable row level security;
drop policy if exists "je vois si je suis testeur" on public.beta_members;
create policy "je vois si je suis testeur" on public.beta_members for select using (auth.uid() = user_id);

create or replace function public.guard_action(p_uid uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_uid is null then raise exception 'not authenticated'; end if;
  if public.is_banned(p_uid) then raise exception 'banned'; end if;
  if coalesce((select (value ->> 'on')::boolean from public.app_settings where key = 'maintenance'), false)
     and not public.is_staff(p_uid) then
    raise exception 'maintenance';
  end if;
  if coalesce((select (value ->> 'on')::boolean from public.app_settings where key = 'beta'), false)
     and not public.is_staff(p_uid)
     and not exists (select 1 from public.beta_members where user_id = p_uid) then
    raise exception 'beta';
  end if;
end;
$$;
revoke all on function public.guard_action(uuid) from public;

-- Ce que le site doit savoir sur moi : bêta privée active ? suis-je admis ?
create or replace function public.my_access()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'beta_on', coalesce((select (value ->> 'on')::boolean from public.app_settings where key = 'beta'), false),
    'allowed', public.is_staff(auth.uid()) or exists (select 1 from public.beta_members where user_id = auth.uid()));
$$;
revoke all on function public.my_access() from public;
grant execute on function public.my_access() to authenticated;

create or replace function public.staff_set_beta(p_on boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  update public.app_settings set value = jsonb_build_object('on', coalesce(p_on, false)) where key = 'beta';
end;
$$;
revoke all on function public.staff_set_beta(boolean) from public;
grant execute on function public.staff_set_beta(boolean) to authenticated;

create or replace function public.staff_beta_add(p_pseudo text)
returns void language plpgsql security definer set search_path = public as $$
declare other uuid := public.uid_of(p_pseudo);
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  if other is null then raise exception 'unknown player'; end if;
  insert into public.beta_members (user_id) values (other) on conflict do nothing;
end;
$$;
revoke all on function public.staff_beta_add(text) from public;
grant execute on function public.staff_beta_add(text) to authenticated;

create or replace function public.staff_beta_remove(p_pseudo text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  delete from public.beta_members where user_id = public.uid_of(p_pseudo);
end;
$$;
revoke all on function public.staff_beta_remove(text) from public;
grant execute on function public.staff_beta_remove(text) to authenticated;

create or replace function public.staff_beta_list()
returns table (pseudo text, added_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  return query select p.pseudo, b.added_at from public.beta_members b join public.profiles p on p.id = b.user_id order by p.pseudo;
end;
$$;
revoke all on function public.staff_beta_list() from public;
grant execute on function public.staff_beta_list() to authenticated;

-- ============ 3. Rôles : seul le fondateur nomme des administrateurs / modérateurs ============
create or replace function public.staff_set_role(p_pseudo text, p_role text)
returns void language plpgsql security definer set search_path = public as $$
declare
  other uuid := public.uid_of(p_pseudo);
begin
  if coalesce(public.my_role(), '') <> 'founder' then raise exception 'forbidden'; end if;
  if other is null then raise exception 'unknown player'; end if;
  if exists (select 1 from public.user_roles where user_id = other and role = 'founder') then raise exception 'cannot change founder'; end if;
  if p_role = 'none' then
    delete from public.user_roles where user_id = other;
  elsif p_role in ('admin', 'moderator') then
    insert into public.user_roles (user_id, role) values (other, p_role)
    on conflict (user_id) do update set role = excluded.role;
  else
    raise exception 'invalid role';
  end if;
end;
$$;
revoke all on function public.staff_set_role(text, text) from public;
grant execute on function public.staff_set_role(text, text) to authenticated;

create or replace function public.staff_list_roles()
returns table (pseudo text, role text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  return query select p.pseudo, r.role from public.user_roles r join public.profiles p on p.id = r.user_id order by r.role, p.pseudo;
end;
$$;
revoke all on function public.staff_list_roles() from public;
grant execute on function public.staff_list_roles() to authenticated;

-- ============ 4. Sauvegarde : toutes les données en un seul fichier (fondateur / administrateur) ============
-- Les mots de passe ne sont PAS inclus (ils restent dans le système d'authentification de Supabase).
create or replace function public.staff_export()
returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  return jsonb_build_object(
    'exported_at', now(),
    'profiles', coalesce((select jsonb_agg(to_jsonb(t)) from public.profiles t), '[]'::jsonb),
    'scores', coalesce((select jsonb_agg(to_jsonb(t)) from public.scores t), '[]'::jsonb),
    'player_stats', coalesce((select jsonb_agg(to_jsonb(t)) from public.player_stats t), '[]'::jsonb),
    'bc_ledger', coalesce((select jsonb_agg(to_jsonb(t)) from public.bc_ledger t), '[]'::jsonb),
    'user_badges', coalesce((select jsonb_agg(to_jsonb(t)) from public.user_badges t), '[]'::jsonb),
    'user_items', coalesce((select jsonb_agg(to_jsonb(t)) from public.user_items t), '[]'::jsonb),
    'login_streaks', coalesce((select jsonb_agg(to_jsonb(t)) from public.login_streaks t), '[]'::jsonb),
    'friendships', coalesce((select jsonb_agg(to_jsonb(t)) from public.friendships t), '[]'::jsonb),
    'season_claims', coalesce((select jsonb_agg(to_jsonb(t)) from public.season_claims t), '[]'::jsonb),
    'news', coalesce((select jsonb_agg(to_jsonb(t)) from public.news t), '[]'::jsonb),
    'bans', coalesce((select jsonb_agg(to_jsonb(t)) from public.bans t), '[]'::jsonb),
    'user_roles', coalesce((select jsonb_agg(to_jsonb(t)) from public.user_roles t), '[]'::jsonb),
    'beta_members', coalesce((select jsonb_agg(to_jsonb(t)) from public.beta_members t), '[]'::jsonb));
end;
$$;
revoke all on function public.staff_export() from public;
grant execute on function public.staff_export() to authenticated;

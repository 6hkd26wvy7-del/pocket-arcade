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
    when 'space' then 100000   -- v17 : 20 000 avant (bloquait les bonnes parties depuis les bonus)
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
-- BOYGAMES schema v6 — sauvegarde complète, contrôle duels, fin des transferts de BC,
-- avatars, badge choisi, blocage, fiches d'amis, badges exclusifs de bêta.
-- Idempotent. NE SUPPRIME AUCUNE DONNÉE (aucun drop table, aucun delete de données).

-- ============ 1. SAUVEGARDE COMPLÈTE + INTÉGRITÉ ============
create or replace function public.staff_export()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  data jsonb;
  integ jsonb := '{}'::jsonb;
  k text;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  data := jsonb_build_object(
    'profiles',      coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.profiles t), '[]'::jsonb),
    'player_stats',  coalesce((select jsonb_agg(to_jsonb(t) order by t.user_id) from public.player_stats t), '[]'::jsonb),
    'scores',        coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.scores t), '[]'::jsonb),
    'bc_ledger',     coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.bc_ledger t), '[]'::jsonb),
    'user_badges',   coalesce((select jsonb_agg(to_jsonb(t) order by t.user_id, t.badge_code) from public.user_badges t), '[]'::jsonb),
    'user_items',    coalesce((select jsonb_agg(to_jsonb(t) order by t.user_id, t.item_code) from public.user_items t), '[]'::jsonb),
    'login_streaks', coalesce((select jsonb_agg(to_jsonb(t) order by t.user_id) from public.login_streaks t), '[]'::jsonb),
    'friendships',   coalesce((select jsonb_agg(to_jsonb(t) order by t.user_a, t.user_b) from public.friendships t), '[]'::jsonb),
    'messages',      coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.messages t), '[]'::jsonb),
    'notifications', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.notifications t), '[]'::jsonb),
    'season_claims', coalesce((select jsonb_agg(to_jsonb(t)) from public.season_claims t), '[]'::jsonb),
    'mission_claims',coalesce((select jsonb_agg(to_jsonb(t)) from public.mission_claims t), '[]'::jsonb),
    'reports',       coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.reports t), '[]'::jsonb),
    'bans',          coalesce((select jsonb_agg(to_jsonb(t)) from public.bans t), '[]'::jsonb),
    'user_roles',    coalesce((select jsonb_agg(to_jsonb(t) order by t.user_id) from public.user_roles t), '[]'::jsonb),
    'beta_members',  coalesce((select jsonb_agg(to_jsonb(t) order by t.user_id) from public.beta_members t), '[]'::jsonb),
    'news',          coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.news t), '[]'::jsonb),
    'banned_words',  coalesce((select jsonb_agg(to_jsonb(t)) from public.banned_words t), '[]'::jsonb),
    'app_settings',  coalesce((select jsonb_agg(to_jsonb(t)) from public.app_settings t), '[]'::jsonb),
    'blocks',        coalesce((select jsonb_agg(to_jsonb(t)) from public.blocks t), '[]'::jsonb)
  );
  for k in select jsonb_object_keys(data) loop
    integ := integ || jsonb_build_object(k, jsonb_build_object(
      'rows', jsonb_array_length(data -> k),
      'md5', md5((data -> k)::text)));
  end loop;
  return jsonb_build_object(
    'format', 'boygames-backup-v2',
    'exported_at', now(),
    'note', 'Contient les donnees de jeu. Les comptes de connexion (emails, mots de passe) restent chez Supabase Auth et ne sont pas dans ce fichier.',
    'integrity', integ,
    'total_rows', (select coalesce(sum((v ->> 'rows')::int), 0) from jsonb_each(integ) e(k, v)),
    'data', data);
end $$;
revoke all on function public.staff_export() from public, anon;
grant execute on function public.staff_export() to authenticated;

-- ============ 3. FIN DES TRANSFERTS DIRECTS DE BC ============
-- Les soldes ne sont pas touchés. Les anciennes notifications "gift" restent lisibles.
drop function if exists public.send_gift(text, int);
drop function if exists public.send_gift(text, integer);

-- equip_item : contrôle bêta / suspension / maintenance
create or replace function public.equip_item(p_code text, p_on boolean default true)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); k text;
begin
  perform public.guard_action(uid);
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
end $$;

-- ============ 2. CONTRÔLE POUR LE SERVEUR DE DUELS ============
create or replace function public.arena_check()
returns boolean language plpgsql stable security definer set search_path = public as $$
begin
  perform public.guard_action(auth.uid());   -- refuse: non connecté, suspendu, maintenance, hors bêta
  return true;
end $$;
revoke all on function public.arena_check() from public, anon;
grant execute on function public.arena_check() to authenticated;

-- ============ 5a. PROFILS : avatar + badge affiché (verrouillés) ============
create table if not exists public.avatars (
  code text primary key,
  name text not null,
  price int not null default 0 check (price >= 0),   -- 0 = gratuit ; >0 = achetable plus tard avec des BC
  sort int not null default 0
);
alter table public.avatars enable row level security;
drop policy if exists "avatars lisibles par tous" on public.avatars;
create policy "avatars lisibles par tous" on public.avatars for select using (true);

insert into public.avatars (code, name, price, sort) values
 ('av_01','Pixel',0,1),('av_02','Fantôme',0,2),('av_03','Robot',0,3),('av_04','Chat',0,4),
 ('av_05','Renard',0,5),('av_06','Alien',0,6),('av_07','Fusée',0,7),('av_08','Couronne',0,8),
 ('av_09','Éclair',0,9),('av_10','Planète',0,10),('av_11','Dragon',0,11),('av_12','Joystick',0,12)
on conflict (code) do nothing;

alter table public.profiles add column if not exists avatar text not null default 'av_01';
alter table public.profiles add column if not exists featured_badge text;

-- plus aucune écriture directe sur le profil : tout passe par des fonctions contrôlées
revoke update on public.profiles from anon, authenticated;
revoke insert on public.profiles from anon, authenticated;
grant insert (id, pseudo, country) on public.profiles to authenticated;

create or replace function public.set_avatar(p_code text)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); a public.avatars;
begin
  perform public.guard_action(uid);
  select * into a from public.avatars where code = p_code;
  if not found then raise exception 'unknown avatar'; end if;
  if a.price > 0 and not exists (select 1 from public.user_items where user_id = uid and item_code = a.code) then
    raise exception 'not owned';
  end if;
  update public.profiles set avatar = a.code where id = uid;
end $$;

create or replace function public.set_featured_badge(p_code text)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  perform public.guard_action(uid);
  if p_code is not null and p_code <> '' and not exists
     (select 1 from public.user_badges where user_id = uid and badge_code = p_code) then
    raise exception 'not owned';
  end if;
  update public.profiles set featured_badge = nullif(p_code, '') where id = uid;
end $$;

-- ============ 6. BADGES EXCLUSIFS ============
alter table public.badges add column if not exists exclusive boolean not null default false;
insert into public.badges (code, name, description, sort, exclusive) values
 ('beta_founder','BÊTA TESTEUR — ÉDITION FONDATRICE','Un des 10 premiers bêta-testeurs de BOYGAMES. Badge unique, impossible à obtenir autrement.',100,true),
 ('founder','FONDATEUR','Le créateur de BOYGAMES.',101,true)
on conflict (code) do update set name = excluded.name, description = excluded.description, exclusive = true;

-- attribution automatique : jamais d'achat, jamais de transfert
create or replace function public.award_exclusive(p_uid uuid)
returns void language plpgsql security definer set search_path = public as $$
declare holders int;
begin
  perform pg_advisory_xact_lock(60601);
  if exists (select 1 from public.user_roles where user_id = p_uid and role = 'founder') then
    insert into public.user_badges (user_id, badge_code) values (p_uid, 'founder') on conflict do nothing;
    return;                                    -- le Fondateur ne prend pas une des 10 places
  end if;
  if exists (select 1 from public.beta_members where user_id = p_uid)
     and not exists (select 1 from public.user_badges where user_id = p_uid and badge_code = 'beta_founder') then
    select count(*) into holders from public.user_badges where badge_code = 'beta_founder';
    if holders < 10 then
      insert into public.user_badges (user_id, badge_code) values (p_uid, 'beta_founder') on conflict do nothing;
    end if;
  end if;
end $$;
revoke all on function public.award_exclusive(uuid) from public, anon, authenticated;

create or replace function public.trg_award_beta() returns trigger language plpgsql security definer set search_path = public as $$
begin perform public.award_exclusive(new.user_id); return new; end $$;
drop trigger if exists award_beta on public.beta_members;
create trigger award_beta after insert on public.beta_members for each row execute function public.trg_award_beta();

create or replace function public.trg_award_role() returns trigger language plpgsql security definer set search_path = public as $$
begin if new.role = 'founder' then perform public.award_exclusive(new.user_id); end if; return new; end $$;
drop trigger if exists award_role on public.user_roles;
create trigger award_role after insert or update on public.user_roles for each row execute function public.trg_award_role();

-- un badge exclusif ne se supprime pas (sauf suppression complète du compte)
create or replace function public.trg_protect_exclusive() returns trigger language plpgsql as $$
begin
  if exists (select 1 from public.badges b where b.code = old.badge_code and b.exclusive)
     and exists (select 1 from auth.users u where u.id = old.user_id) then
    raise exception 'exclusive badge is permanent';
  end if;
  if tg_op = 'UPDATE' then return new; end if;
  return old;
end $$;
drop trigger if exists protect_exclusive on public.user_badges;
create trigger protect_exclusive before delete or update on public.user_badges
  for each row execute function public.trg_protect_exclusive();

-- attribution rétroactive : testeurs déjà autorisés, dans l'ordre d'arrivée (max 10) + Fondateur
do $$
declare r record;
begin
  for r in select user_id from public.user_roles where role = 'founder' loop
    perform public.award_exclusive(r.user_id);
  end loop;
  for r in select user_id from public.beta_members order by added_at, user_id loop
    perform public.award_exclusive(r.user_id);
  end loop;
end $$;

-- ============ 5b. BLOCAGE ============
create table if not exists public.blocks (
  blocker uuid not null references auth.users(id) on delete cascade,
  blocked uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker, blocked),
  check (blocker <> blocked)
);
alter table public.blocks enable row level security;
drop policy if exists "je vois mes blocages" on public.blocks;
create policy "je vois mes blocages" on public.blocks for select using (auth.uid() = blocker);

create or replace function public.is_blocked_between(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.blocks where (blocker = a and blocked = b) or (blocker = b and blocked = a));
$$;
revoke all on function public.is_blocked_between(uuid, uuid) from public, anon, authenticated;

create or replace function public.block_user(p_pseudo text)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); other uuid;
begin
  perform public.guard_action(uid);
  other := public.uid_of(p_pseudo);
  if other is null then raise exception 'unknown player'; end if;
  if other = uid then raise exception 'cannot block yourself'; end if;
  insert into public.blocks (blocker, blocked) values (uid, other) on conflict do nothing;
  delete from public.friendships where user_a = least(uid, other) and user_b = greatest(uid, other);
end $$;

create or replace function public.unblock_user(p_pseudo text)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); other uuid;
begin
  perform public.guard_action(uid);
  other := public.uid_of(p_pseudo);
  if other is null then raise exception 'unknown player'; end if;
  delete from public.blocks where blocker = uid and blocked = other;
end $$;

create or replace function public.my_blocks()
returns table (pseudo text) language sql stable security definer set search_path = public as $$
  select p.pseudo from public.blocks b join public.profiles p on p.id = b.blocked
  where b.blocker = auth.uid() order by p.pseudo;
$$;

create or replace function public.send_message(p_pseudo text, p_body text)
returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); other uuid; txt text := trim(coalesce(p_body, ''));
begin
  perform public.guard_action(uid);
  other := public.uid_of(p_pseudo);
  if other is null then raise exception 'unknown player'; end if;
  if public.is_blocked_between(uid, other) then raise exception 'blocked'; end if;
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
end $$;

create or replace function public.send_friend_request(p_pseudo text)
returns text language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); other uuid; fr public.friendships; pending_out int;
begin
  perform public.guard_action(uid);
  other := public.uid_of(p_pseudo);
  if other is null then raise exception 'unknown player'; end if;
  if other = uid then raise exception 'cannot add yourself'; end if;
  if public.is_blocked_between(uid, other) then raise exception 'blocked'; end if;
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
end $$;

-- ============ 5c. LISTE D'AMIS + FICHE ============
drop function if exists public.my_friends();
create or replace function public.my_friends()
returns table (pseudo text, level int, relation text, avatar text, featured_badge text)
language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'not authenticated'; end if;
  return query
  select p.pseudo, coalesce(s.level, 1),
         case when f.status = 'accepted' then 'friend'
              when f.requested_by <> auth.uid() then 'incoming' else 'outgoing' end,
         p.avatar, p.featured_badge
  from public.friendships f
  join public.profiles p on p.id = case when f.user_a = auth.uid() then f.user_b else f.user_a end
  left join public.player_stats s on s.user_id = p.id
  where auth.uid() in (f.user_a, f.user_b)
  order by case when f.status = 'accepted' then 1 when f.requested_by <> auth.uid() then 0 else 2 end, p.pseudo;
end $$;

-- Fiche de joueur. Jamais d'email, de BOYCOINS, de messages. Stats et badges : amis et soi-même seulement.
create or replace function public.public_profile(p_pseudo text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); other uuid; rel text; full_view boolean;
  p public.profiles; s public.player_stats; fb jsonb; tt jsonb;
begin
  perform public.guard_action(uid);
  other := public.uid_of(p_pseudo);
  if other is null or public.is_blocked_between(uid, other) then raise exception 'unknown player'; end if;
  select * into p from public.profiles where id = other;
  select * into s from public.player_stats where user_id = other;
  rel := case
    when other = uid then 'self'
    when public.are_friends(uid, other) then 'friend'
    when exists (select 1 from public.friendships f where f.user_a = least(uid, other) and f.user_b = greatest(uid, other)) then 'pending'
    else 'none' end;
  full_view := rel in ('self', 'friend');
  select jsonb_build_object('code', b.code, 'name', b.name) into fb
    from public.badges b join public.user_badges ub on ub.badge_code = b.code
   where ub.user_id = other and b.code = p.featured_badge;
  select jsonb_build_object('code', si.code, 'name', si.name) into tt
    from public.user_items ui join public.shop_items si on si.code = ui.item_code
   where ui.user_id = other and ui.equipped and si.kind = 'title' limit 1;
  return jsonb_build_object(
    'pseudo', p.pseudo, 'avatar', p.avatar, 'level', coalesce(s.level, 1),
    'relation', rel, 'featured_badge', fb, 'title', tt,
    'member_since', p.created_at,
    'xp', case when full_view then coalesce(s.xp, 0) end,
    'level_start_xp', 50 * (coalesce(s.level,1) - 1) * (coalesce(s.level,1) - 1),
    'next_level_xp', 50 * coalesce(s.level,1) * coalesce(s.level,1),
    'badges', case when full_view then coalesce((select jsonb_agg(ub.badge_code order by ub.earned_at)
                    from public.user_badges ub where ub.user_id = other), '[]'::jsonb) end,
    'games', case when full_view then coalesce((select jsonb_agg(jsonb_build_object('game', g.game, 'best', g.best, 'plays', g.plays) order by g.game)
                    from (select game, max(score) best, count(*) plays from public.scores where user_id = other group by game) g), '[]'::jsonb) end);
end $$;

-- me() : ajoute avatar + badge affiché
create or replace function public.me()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'pseudo', p.pseudo, 'country', p.country, 'avatar', p.avatar, 'featured_badge', p.featured_badge,
    'xp', s.xp, 'level', s.level,
    'level_start_xp', 50 * (s.level - 1) * (s.level - 1),
    'next_level_xp', 50 * s.level * s.level,
    'bc', s.bc,
    'badges', coalesce((select jsonb_agg(ub.badge_code order by ub.earned_at) from public.user_badges ub where ub.user_id = p.id), '[]'::jsonb),
    'items', coalesce((select jsonb_agg(jsonb_build_object('code', ui.item_code, 'equipped', ui.equipped)) from public.user_items ui where ui.user_id = p.id), '[]'::jsonb),
    'streak', coalesce((select ls.streak from public.login_streaks ls where ls.user_id = p.id), 0),
    'daily_claimed_today', coalesce((select ls.last_claim = (now() at time zone 'Europe/Paris')::date from public.login_streaks ls where ls.user_id = p.id), false)
  )
  from public.profiles p join public.player_stats s on s.user_id = p.id
  where p.id = auth.uid();
$$;

-- droits d'exécution
revoke all on function public.set_avatar(text), public.set_featured_badge(text), public.block_user(text),
  public.unblock_user(text), public.my_blocks(), public.my_friends(), public.public_profile(text), public.me()
  from public, anon;
grant execute on function public.set_avatar(text), public.set_featured_badge(text), public.block_user(text),
  public.unblock_user(text), public.my_blocks(), public.my_friends(), public.public_profile(text), public.me()
  to authenticated;

-- durcissement : fonctions de trigger non appelables par l'API, tables neuves en lecture seule pour les joueurs
revoke all on function public.trg_award_beta(), public.trg_award_role(), public.trg_protect_exclusive() from public, anon, authenticated;
revoke insert, update, delete, truncate on public.avatars, public.blocks from anon, authenticated;

-- BOYGAMES schema v7 — « Signaler un bug » (additif : une table, des fonctions). Idempotent.
-- Dépend de v1–v6. Ne modifie ni ne supprime aucune donnée existante.

create table if not exists public.bug_reports (
  id bigint generated always as identity primary key,
  user_id uuid references auth.users(id) on delete set null,   -- on garde le signalement si le compte est supprimé
  pseudo text not null default '',
  category text not null check (category in ('game','display','account','friends','boycoins','other')),
  description text not null check (char_length(description) between 10 and 2000),
  page text not null default '' check (char_length(page) <= 120),
  game text not null default '' check (char_length(game) <= 40),
  app_version text not null default '' check (char_length(app_version) <= 60),
  device jsonb not null default '{}'::jsonb check (pg_column_size(device) <= 6000),
  screenshot text check (screenshot is null or (char_length(screenshot) <= 300000 and screenshot like 'data:image/jpeg;base64,%')),
  status text not null default 'new' check (status in ('new','in_progress','resolved','wontfix')),
  priority text not null default 'normal' check (priority in ('low','normal','high','blocker')),
  admin_note text not null default '' check (char_length(admin_note) <= 1000),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists bug_reports_status on public.bug_reports (status, created_at desc);
alter table public.bug_reports enable row level security;
drop policy if exists "je vois mes signalements" on public.bug_reports;
create policy "je vois mes signalements" on public.bug_reports for select using (auth.uid() = user_id);

-- Envoi : connecté et non suspendu. Reste possible pendant la maintenance (c'est justement utile).
create or replace function public.submit_bug_report(
  p_category text, p_description text, p_page text default '', p_game text default '',
  p_app_version text default '', p_device jsonb default '{}'::jsonb, p_screenshot text default null)
returns bigint language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); new_id bigint; txt text := trim(coalesce(p_description, ''));
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if public.is_banned(uid) then raise exception 'banned'; end if;
  if char_length(txt) < 10 or char_length(txt) > 2000 then raise exception 'invalid description'; end if;
  if p_category not in ('game','display','account','friends','boycoins','other') then raise exception 'invalid category'; end if;
  if (select count(*) from public.bug_reports where user_id = uid and created_at > now() - interval '1 hour') >= 10
     or (select count(*) from public.bug_reports where user_id = uid and created_at > now() - interval '1 day') >= 30 then
    raise exception 'too many reports';
  end if;
  insert into public.bug_reports (user_id, pseudo, category, description, page, game, app_version, device, screenshot)
  values (uid, coalesce(public.pseudo_of(uid), ''), p_category, txt,
          left(coalesce(p_page, ''), 120), left(coalesce(p_game, ''), 40), left(coalesce(p_app_version, ''), 60),
          coalesce(p_device, '{}'::jsonb), nullif(p_screenshot, ''))
  returning id into new_id;
  return new_id;
end $$;

-- Équipe (fondateur/admin) : liste SANS les captures (lourdes), chargées à la demande.
create or replace function public.staff_bug_list(p_status text default null)
returns table (id bigint, created_at timestamptz, pseudo text, category text, description text, page text, game text,
               app_version text, device jsonb, has_screenshot boolean, status text, priority text, admin_note text)
language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  return query
    select b.id, b.created_at, b.pseudo, b.category, b.description, b.page, b.game, b.app_version, b.device,
           (b.screenshot is not null), b.status, b.priority, b.admin_note
    from public.bug_reports b
    where p_status is null or p_status = '' or b.status = p_status
    order by (b.status in ('resolved','wontfix')),
             case b.priority when 'blocker' then 0 when 'high' then 1 when 'normal' then 2 else 3 end,
             b.created_at desc
    limit 200;
end $$;

create or replace function public.staff_bug_screenshot(p_id bigint)
returns text language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  return (select screenshot from public.bug_reports where id = p_id);
end $$;

create or replace function public.staff_bug_update(p_id bigint, p_status text, p_priority text, p_note text default '')
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  if p_status not in ('new','in_progress','resolved','wontfix') then raise exception 'invalid status'; end if;
  if p_priority not in ('low','normal','high','blocker') then raise exception 'invalid priority'; end if;
  update public.bug_reports
     set status = p_status, priority = p_priority, admin_note = left(coalesce(p_note, ''), 1000), updated_at = now()
   where id = p_id;
end $$;

create or replace function public.staff_bug_counts()
returns table (status text, n bigint) language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  return query select b.status, count(*) from public.bug_reports b group by b.status;
end $$;

revoke all on function public.submit_bug_report(text, text, text, text, text, jsonb, text),
  public.staff_bug_list(text), public.staff_bug_screenshot(bigint),
  public.staff_bug_update(bigint, text, text, text), public.staff_bug_counts() from public, anon;
grant execute on function public.submit_bug_report(text, text, text, text, text, jsonb, text),
  public.staff_bug_list(text), public.staff_bug_screenshot(bigint),
  public.staff_bug_update(bigint, text, text, text), public.staff_bug_counts() to authenticated;

-- La sauvegarde inclut maintenant les signalements (sans les captures, trop lourdes : seulement un indicateur).
create or replace function public.staff_export()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare data jsonb; integ jsonb := '{}'::jsonb; k text;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  data := jsonb_build_object(
    'profiles',      coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.profiles t), '[]'::jsonb),
    'player_stats',  coalesce((select jsonb_agg(to_jsonb(t) order by t.user_id) from public.player_stats t), '[]'::jsonb),
    'scores',        coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.scores t), '[]'::jsonb),
    'bc_ledger',     coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.bc_ledger t), '[]'::jsonb),
    'user_badges',   coalesce((select jsonb_agg(to_jsonb(t) order by t.user_id, t.badge_code) from public.user_badges t), '[]'::jsonb),
    'user_items',    coalesce((select jsonb_agg(to_jsonb(t) order by t.user_id, t.item_code) from public.user_items t), '[]'::jsonb),
    'login_streaks', coalesce((select jsonb_agg(to_jsonb(t) order by t.user_id) from public.login_streaks t), '[]'::jsonb),
    'friendships',   coalesce((select jsonb_agg(to_jsonb(t) order by t.user_a, t.user_b) from public.friendships t), '[]'::jsonb),
    'messages',      coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.messages t), '[]'::jsonb),
    'notifications', coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.notifications t), '[]'::jsonb),
    'season_claims', coalesce((select jsonb_agg(to_jsonb(t)) from public.season_claims t), '[]'::jsonb),
    'mission_claims',coalesce((select jsonb_agg(to_jsonb(t)) from public.mission_claims t), '[]'::jsonb),
    'reports',       coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.reports t), '[]'::jsonb),
    'bans',          coalesce((select jsonb_agg(to_jsonb(t)) from public.bans t), '[]'::jsonb),
    'user_roles',    coalesce((select jsonb_agg(to_jsonb(t) order by t.user_id) from public.user_roles t), '[]'::jsonb),
    'beta_members',  coalesce((select jsonb_agg(to_jsonb(t) order by t.user_id) from public.beta_members t), '[]'::jsonb),
    'news',          coalesce((select jsonb_agg(to_jsonb(t) order by t.id) from public.news t), '[]'::jsonb),
    'banned_words',  coalesce((select jsonb_agg(to_jsonb(t)) from public.banned_words t), '[]'::jsonb),
    'app_settings',  coalesce((select jsonb_agg(to_jsonb(t)) from public.app_settings t), '[]'::jsonb),
    'blocks',        coalesce((select jsonb_agg(to_jsonb(t)) from public.blocks t), '[]'::jsonb),
    'bug_reports',   coalesce((select jsonb_agg(to_jsonb(t) - 'screenshot' || jsonb_build_object('has_screenshot', t.screenshot is not null) order by t.id) from public.bug_reports t), '[]'::jsonb)
  );
  for k in select jsonb_object_keys(data) loop
    integ := integ || jsonb_build_object(k, jsonb_build_object('rows', jsonb_array_length(data -> k), 'md5', md5((data -> k)::text)));
  end loop;
  return jsonb_build_object('format', 'boygames-backup-v2', 'exported_at', now(),
    'note', 'Contient les donnees de jeu. Les comptes de connexion (emails, mots de passe) restent chez Supabase Auth et ne sont pas dans ce fichier. Les captures d ecran des signalements ne sont pas incluses.',
    'integrity', integ,
    'total_rows', (select coalesce(sum((v ->> 'rows')::int), 0) from jsonb_each(integ) e(k, v)),
    'data', data);
end $$;
revoke all on function public.staff_export() from public, anon;
grant execute on function public.staff_export() to authenticated;

revoke insert, update, delete, truncate on public.bug_reports from anon, authenticated;

-- BOYGAMES — DURCISSEMENT DES DROITS (liste blanche). Idempotent.
-- Problème corrigé : sur Supabase, les nouvelles fonctions sont par défaut exécutables par tout joueur
-- connecté (et même par les visiteurs). "revoke ... from public" ne retire PAS ces droits. Des fonctions
-- internes (add_bc, add_xp, check_badges...) pouvaient donc être appelées directement.
-- Désormais : AUCUNE fonction n'est appelable, sauf la liste blanche ci-dessous.
do $$
declare r record;
  api text[] := array['arena_check', 'beta_mission_set', 'beta_redeem', 'beta_space', 'beta_survey_get', 'beta_survey_save', 'block_user', 'boyblocks_finish', 'boyblocks_start', 'boyblocks_start_v2', 'boyblocks_start_v3', 'game_settings_public', 'my_tiers', 'public_tiers', 'set_favorites', 'sync_tiers', 'buy_item', 'claim_daily', 'claim_mission', 'claim_season_rewards', 'conversation', 'delete_my_account', 'economy_public', 'equip_item', 'get_maintenance', 'leaderboard', 'leaderboard_friends', 'leaderboard_season', 'mark_notifications_read', 'me', 'monetization_public', 'my_access', 'my_blocks', 'my_friends', 'my_missions', 'my_notifications', 'my_role', 'my_season_rewards', 'my_standing', 'public_profile', 'remove_friend', 'report_user', 'rewarded_continue', 'respond_friend_request', 'send_friend_request', 'send_message', 'set_avatar', 'set_featured_badge', 'submit_bug_report', 'submit_continued_score', 'game_start', 'submit_score_v2', 'unblock_user'];
  anon_ok text[] := array['get_maintenance','leaderboard','leaderboard_season','monetization_public','game_settings_public'];
begin
  revoke execute on all functions in schema public from public, anon, authenticated;
  -- joueurs connectés : l'API du site + les fonctions d'équipe (chacune vérifie elle-même le rôle admin)
  for r in select p.oid::regprocedure as sig from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
              and (p.proname = any(api) or p.proname like 'staff\_%') loop
    execute format('grant execute on function %s to authenticated', r.sig);
  end loop;
  -- visiteurs non connectés : uniquement des lectures publiques
  for r in select p.oid::regprocedure as sig from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' and p.proname = any(anon_ok) loop
    execute format('grant execute on function %s to anon', r.sig);
  end loop;
end $$;

-- Les futures fonctions et tables ne recevront plus de droits automatiques.
alter default privileges in schema public revoke execute on functions from public, anon, authenticated;
alter default privileges in schema public revoke insert, update, delete, truncate on tables from anon, authenticated;

-- Tables : plus aucune écriture directe par les joueurs (tout passe par des fonctions contrôlées).
-- Seule exception voulue : la création de son propre profil (id, pseudo, pays).
revoke insert, update, delete, truncate on all tables in schema public from anon, authenticated;
grant insert (id, pseudo, country) on public.profiles to authenticated;

-- ===== v8 : BoyBlocks =====
-- BOYGAMES schema v8 — BOYBLOCKS : parties vérifiées côté base (aucun score envoyé par le téléphone n'est cru).
-- Principe : le serveur donne la graine (le "tirage" des pièces), le joueur envoie la liste de ses coups,
-- la base REJOUE la partie avec exactement les mêmes règles que le jeu, et calcule elle-même le score.
-- Additif et idempotent. Dépend de v1–v7. Aucune donnée existante n'est modifiée.

create table if not exists public.bb_shapes (
  id int primary key, name text not null, weight int not null, h int not null, w int not null, n int not null,
  cells int[] not null            -- [ligne,colonne, ligne,colonne, ...] complété par -1
);
alter table public.bb_shapes enable row level security;     -- aucune règle de lecture : table interne
revoke all on public.bb_shapes from anon, authenticated;
insert into public.bb_shapes (id, name, weight, h, w, n, cells) values
  (0, 'dot', 3, 1, 1, 1, '{0,0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (1, 'h2', 6, 1, 2, 2, '{0,0,0,1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (2, 'v2', 6, 2, 1, 2, '{0,0,1,0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (3, 'h3', 7, 1, 3, 3, '{0,0,0,1,0,2,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (4, 'v3', 7, 3, 1, 3, '{0,0,1,0,2,0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (5, 'h4', 4, 1, 4, 4, '{0,0,0,1,0,2,0,3,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (6, 'v4', 4, 4, 1, 4, '{0,0,1,0,2,0,3,0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (7, 'h5', 2, 1, 5, 5, '{0,0,0,1,0,2,0,3,0,4,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (8, 'v5', 2, 5, 1, 5, '{0,0,1,0,2,0,3,0,4,0,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (9, 'sq2', 6, 2, 2, 4, '{0,0,0,1,1,0,1,1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (10, 'sq3', 2, 3, 3, 9, '{0,0,0,1,0,2,1,0,1,1,1,2,2,0,2,1,2,2}'),
  (11, 'r23', 3, 2, 3, 6, '{0,0,0,1,0,2,1,0,1,1,1,2,-1,-1,-1,-1,-1,-1}'),
  (12, 'r32', 3, 3, 2, 6, '{0,0,0,1,1,0,1,1,2,0,2,1,-1,-1,-1,-1,-1,-1}'),
  (13, 'c2a', 5, 2, 2, 3, '{0,0,0,1,1,0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (14, 'c2b', 5, 2, 2, 3, '{0,0,0,1,1,1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (15, 'c2c', 5, 2, 2, 3, '{0,0,1,0,1,1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (16, 'c2d', 5, 2, 2, 3, '{0,1,1,0,1,1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (17, 'c3a', 3, 3, 3, 5, '{0,0,0,1,0,2,1,0,2,0,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (18, 'c3b', 3, 3, 3, 5, '{0,0,0,1,0,2,1,2,2,2,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (19, 'c3c', 3, 3, 3, 5, '{0,0,1,0,2,0,2,1,2,2,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (20, 'c3d', 3, 3, 3, 5, '{0,2,1,2,2,0,2,1,2,2,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (21, 't3a', 3, 2, 3, 4, '{0,0,0,1,0,2,1,1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (22, 't3b', 3, 2, 3, 4, '{0,1,1,0,1,1,1,2,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (23, 't3c', 3, 3, 2, 4, '{0,0,1,0,1,1,2,0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (24, 't3d', 3, 3, 2, 4, '{0,1,1,0,1,1,2,1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (25, 'z2a', 2, 2, 3, 4, '{0,0,0,1,1,1,1,2,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (26, 'z2b', 2, 2, 3, 4, '{0,1,0,2,1,0,1,1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (27, 'z2c', 2, 3, 2, 4, '{0,1,1,0,1,1,2,0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}'),
  (28, 'z2d', 2, 3, 2, 4, '{0,0,1,0,1,1,2,1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1}')
on conflict (id) do update set name = excluded.name, weight = excluded.weight, h = excluded.h, w = excluded.w, n = excluded.n, cells = excluded.cells;

create table if not exists public.boyblocks_runs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  seed bigint not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  score int, moves int
);
create index if not exists boyblocks_runs_user on public.boyblocks_runs (user_id, started_at desc);
alter table public.boyblocks_runs enable row level security;
revoke all on public.boyblocks_runs from anon, authenticated;

-- ===== moteur (miroir exact de shared/boyblocks-engine.js ; vérifié par comparaison automatique) =====
create or replace function public.bb_imul(a bigint, b bigint) returns bigint language sql immutable as $$
  select (((a & 65535) * b) + ((((a >> 16) * b) & 65535) << 16)) & 4294967295
$$;

create or replace function public.bb_step(a bigint, out o_a bigint, out o_v double precision) language plpgsql immutable as $$
declare t bigint;
begin
  o_a := (a + 1831565813) & 4294967295;
  t := o_a;
  t := public.bb_imul(t # (t >> 15), t | 1);
  t := t # ((t + public.bb_imul(t # (t >> 7), t | 61)) & 4294967295);
  o_v := ((t # (t >> 14)) & 4294967295)::double precision / 4294967296.0;
end $$;

create or replace function public.bb_mix(seed bigint, idx int, salt int) returns bigint language plpgsql immutable as $$
declare h bigint;
begin
  h := (seed # public.bb_imul(idx + 1, 2654435761) # public.bb_imul(salt + 1, 2246822507)) & 4294967295;
  h := public.bb_imul(h # (h >> 16), 2146121005);
  h := public.bb_imul(h # (h >> 15), 2221713035);
  return (h # (h >> 16)) & 4294967295;
end $$;

create or replace function public.bb_fits(grid int[], shp int[], shn int[], id int, r int, c int) returns boolean language plpgsql immutable as $$
declare i int; rr int; cc int;
begin
  for i in 0 .. shn[id + 1] - 1 loop
    rr := r + shp[id + 1][2 * i + 1]; cc := c + shp[id + 1][2 * i + 2];
    if rr < 0 or cc < 0 or rr >= 8 or cc >= 8 or grid[rr * 8 + cc + 1] <> 0 then return false; end if;
  end loop;
  return true;
end $$;

create or replace function public.bb_can(grid int[], shp int[], shn int[], shh int[], shw int[], id int) returns boolean language plpgsql immutable as $$
declare r int; c int;
begin
  for r in 0 .. 8 - shh[id + 1] loop
    for c in 0 .. 8 - shw[id + 1] loop
      if public.bb_fits(grid, shp, shn, id, r, c) then return true; end if;
    end loop;
  end loop;
  return false;
end $$;

-- lot n°idx : 6 entiers = 3 pièces puis 3 couleurs
create or replace function public.bb_deal(seed bigint, idx int, grid int[], ensure boolean, shp int[], shn int[], shh int[], shw int[], shwt int[], total int)
returns int[] language plpgsql immutable as $$
declare salt int; st bigint; v double precision; p int[3]; col int[3]; k int; x double precision; j int; res int[]; ok boolean;
begin
  for salt in 0 .. (case when ensure then 11 else 0 end) loop
    st := public.bb_mix(seed, idx, salt);
    for k in 1 .. 3 loop
      select o_a, o_v into st, v from public.bb_step(st);
      x := v * total; p[k] := array_length(shwt, 1) - 1;
      for j in 1 .. array_length(shwt, 1) loop
        x := x - shwt[j];
        if x < 0 then p[k] := j - 1; exit; end if;
      end loop;
    end loop;
    for k in 1 .. 3 loop
      select o_a, o_v into st, v from public.bb_step(st);
      col[k] := 1 + floor(v * 7)::int;
    end loop;
    res := array[p[1], p[2], p[3], col[1], col[2], col[3]];
    ok := public.bb_can(grid, shp, shn, shh, shw, p[1]) or public.bb_can(grid, shp, shn, shh, shw, p[2]) or public.bb_can(grid, shp, shn, shh, shw, p[3]);
    if not ensure or ok then return res; end if;
  end loop;
  return res;
end $$;

create or replace function public.bb_replay(p_seed bigint, p_moves jsonb, p_ensure boolean default true)
returns table (ok boolean, err text, at int, score int, moves int, lines int, best_streak int, over boolean)
language plpgsql stable as $$
declare
  shwt int[]; shn int[]; shh int[]; shw int[]; shp int[]; total int;
  grid int[] := array_fill(0, array[64]);
  pc int[]; g_score int := 0; streak int := 0; best int := 0; nlines int := 0; nmoves int := 0; idx int := 0; is_over boolean;
  i int; m jsonb; slot int; r int; c int; id int; k int; rr int; cc int; n int; gain int; clr int;
  rows_full boolean[]; cols_full boolean[]; full boolean; any_left boolean; mult numeric;
begin
  select array_agg(weight order by s.id), array_agg(s.n order by s.id), array_agg(h order by s.id), array_agg(w order by s.id), array_agg(cells order by s.id), sum(weight)::int
    into shwt, shn, shh, shw, shp, total from public.bb_shapes s;
  if p_moves is null or jsonb_typeof(p_moves) <> 'array' or jsonb_array_length(p_moves) > 3000 then
    return query select false, 'moves', 0, 0, 0, 0, 0, false; return;
  end if;
  pc := public.bb_deal(p_seed, 0, grid, p_ensure, shp, shn, shh, shw, shwt, total);
  is_over := not (public.bb_can(grid, shp, shn, shh, shw, pc[1]) or public.bb_can(grid, shp, shn, shh, shw, pc[2]) or public.bb_can(grid, shp, shn, shh, shw, pc[3]));
  for i in 0 .. jsonb_array_length(p_moves) - 1 loop
    if is_over then return query select false, 'over', i, g_score, nmoves, nlines, best, is_over; return; end if;
    m := p_moves -> i;
    if jsonb_typeof(m) <> 'array' or jsonb_array_length(m) <> 3
       or (m ->> 0) !~ '^[0-9]+$' or (m ->> 1) !~ '^-?[0-9]+$' or (m ->> 2) !~ '^-?[0-9]+$' then
      return query select false, 'pos', i, g_score, nmoves, nlines, best, is_over; return;
    end if;
    slot := (m ->> 0)::int; r := (m ->> 1)::int; c := (m ->> 2)::int;
    if slot > 2 or pc[slot + 1] < 0 then return query select false, 'slot', i, g_score, nmoves, nlines, best, is_over; return; end if;
    id := pc[slot + 1];
    if not public.bb_fits(grid, shp, shn, id, r, c) then return query select false, 'fit', i, g_score, nmoves, nlines, best, is_over; return; end if;
    clr := pc[4 + slot];
    for k in 0 .. shn[id + 1] - 1 loop
      grid[(r + shp[id + 1][2 * k + 1]) * 8 + (c + shp[id + 1][2 * k + 2]) + 1] := clr;
    end loop;
    gain := shn[id + 1];
    rows_full := array_fill(true, array[8]); cols_full := array_fill(true, array[8]); n := 0;
    for rr in 0 .. 7 loop
      for cc in 0 .. 7 loop
        if grid[rr * 8 + cc + 1] = 0 then rows_full[rr + 1] := false; cols_full[cc + 1] := false; end if;
      end loop;
    end loop;
    for rr in 1 .. 8 loop
      if rows_full[rr] then n := n + 1; end if;
      if cols_full[rr] then n := n + 1; end if;
    end loop;
    if n > 0 then
      for rr in 0 .. 7 loop
        for cc in 0 .. 7 loop
          if rows_full[rr + 1] or cols_full[cc + 1] then grid[rr * 8 + cc + 1] := 0; end if;
        end loop;
      end loop;
      streak := streak + 1;
      if streak > best then best := streak; end if;
      mult := least(4, 1 + 0.5 * (streak - 1));
      gain := gain + floor(5 * n * (n + 1) * mult + 0.5)::int;
      nlines := nlines + n;
      any_left := false;
      for k in 1 .. 64 loop if grid[k] <> 0 then any_left := true; exit; end if; end loop;
      if not any_left then gain := gain + 300; end if;
    else
      streak := 0;
    end if;
    g_score := g_score + gain; nmoves := nmoves + 1;
    pc[slot + 1] := -1;
    if pc[1] < 0 and pc[2] < 0 and pc[3] < 0 then
      idx := idx + 1;
      pc := public.bb_deal(p_seed, idx, grid, p_ensure, shp, shn, shh, shw, shwt, total);
    end if;
    is_over := not ((pc[1] >= 0 and public.bb_can(grid, shp, shn, shh, shw, pc[1])) or (pc[2] >= 0 and public.bb_can(grid, shp, shn, shh, shw, pc[2])) or (pc[3] >= 0 and public.bb_can(grid, shp, shn, shh, shw, pc[3])));
  end loop;
  return query select true, null::text, null::int, g_score, nmoves, nlines, best, is_over;
end $$;

-- ===== récompenses (même logique que submit_score : plafond de 150 BC/jour pour les parties) =====
create or replace function public.bb_award(p_uid uuid, p_score int) returns jsonb language plpgsql security definer set search_path = public as $$
declare today date := (now() at time zone 'Europe/Paris')::date; xp_gain int; bc_gain int; earned_today int; before_level int; after_level int; badges text[];
begin
  insert into public.player_stats (user_id) values (p_uid) on conflict do nothing;
  insert into public.scores (user_id, game, score) values (p_uid, 'boyblocks', p_score);
  xp_gain := 5 + least(p_score / 80, 60);
  bc_gain := 1 + least(p_score / 400, 25);
  select coalesce(sum(delta), 0) into earned_today from public.bc_ledger
   where user_id = p_uid and reason = 'game' and (created_at at time zone 'Europe/Paris')::date = today;
  bc_gain := least(bc_gain, greatest(0, 150 - earned_today));
  select level into before_level from public.player_stats where user_id = p_uid;
  perform public.add_xp(p_uid, xp_gain);
  if bc_gain > 0 then perform public.add_bc(p_uid, bc_gain, 'game'); end if;
  select level into after_level from public.player_stats where user_id = p_uid;
  badges := public.check_badges(p_uid);
  return jsonb_build_object('xp', xp_gain, 'bc', bc_gain, 'level', after_level, 'level_up', after_level > before_level, 'new_badges', to_jsonb(badges));
end $$;

-- ===== API joueurs =====
create or replace function public.boyblocks_start() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); rid uuid; s bigint;
begin
  perform public.guard_action(uid);
  if (select count(*) from public.boyblocks_runs where user_id = uid and finished_at is null and started_at > now() - interval '1 hour') >= 12 then
    raise exception 'too many runs';
  end if;
  s := floor(random() * 4294967296)::bigint;
  insert into public.boyblocks_runs (user_id, seed) values (uid, s) returning id into rid;
  return jsonb_build_object('run_id', rid, 'seed', s);
end $$;

create or replace function public.boyblocks_finish(p_run uuid, p_moves jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); run public.boyblocks_runs; res record; aw jsonb; secs numeric;
begin
  perform public.guard_action(uid);
  select * into run from public.boyblocks_runs where id = p_run and user_id = uid for update;
  if not found or run.finished_at is not null then raise exception 'invalid run'; end if;
  if run.started_at < now() - interval '6 hours' then raise exception 'run expired'; end if;
  select * into res from public.bb_replay(run.seed, p_moves, true);
  if not res.ok or res.moves < 1 then raise exception 'invalid run'; end if;
  secs := extract(epoch from (now() - run.started_at));
  if secs < res.moves * 0.2 then raise exception 'invalid run'; end if;       -- impossible de jouer aussi vite
  if res.score > 2000000 then raise exception 'invalid score'; end if;
  update public.boyblocks_runs set finished_at = now(), score = res.score, moves = res.moves where id = p_run;
  aw := public.bb_award(uid, res.score);
  return aw || jsonb_build_object('score', res.score, 'lines', res.lines, 'moves', res.moves, 'best_streak', res.best_streak, 'over', res.over);
end $$;

-- droits : explicites (aucune exécution par défaut)
revoke all on function public.bb_imul(bigint, bigint), public.bb_step(bigint), public.bb_mix(bigint, int, int),
  public.bb_fits(int[], int[], int[], int, int, int), public.bb_can(int[], int[], int[], int[], int[], int),
  public.bb_deal(bigint, int, int[], boolean, int[], int[], int[], int[], int[], int),
  public.bb_replay(bigint, jsonb, boolean), public.bb_award(uuid, int) from public, anon, authenticated;
revoke all on function public.boyblocks_start(), public.boyblocks_finish(uuid, jsonb) from public, anon;
grant execute on function public.boyblocks_start(), public.boyblocks_finish(uuid, jsonb) to authenticated;

-- missions BoyBlocks (même mécanique que les missions existantes)
insert into public.missions (code, name, kind, game, goal, reward_bc, reward_xp, sort) values
  ('bb_1500', 'Fais 1500 points à BoyBlocks', 'best_score', 'boyblocks', 1500, 30, 30, 4)
on conflict (code) do update set name = excluded.name, kind = excluded.kind, game = excluded.game, goal = excluded.goal,
  reward_bc = excluded.reward_bc, reward_xp = excluded.reward_xp, sort = excluded.sort;

-- ===== v9 : badges à paliers =====
-- BOYGAMES schema v9 — BADGES À PALIERS (6 niveaux par jeu : Recrue, Argent, Or, Platine, Diamant, Légende).
-- Additif et idempotent. Ne modifie, ne supprime et n'écrase AUCUN badge ni aucune récompense existants
-- (user_badges, badges, check_badges ne sont pas touchés). Dépend de v1–v8.

create table if not exists public.badge_tracks (
  game text not null, tier int not null check (tier between 0 and 5), name text not null,
  min_score int not null, min_plays int not null,
  primary key (game, tier)
);
alter table public.badge_tracks enable row level security;
drop policy if exists "paliers lisibles par tous" on public.badge_tracks;
create policy "paliers lisibles par tous" on public.badge_tracks for select using (true);
revoke insert, update, delete, truncate on public.badge_tracks from anon, authenticated;

-- Seuils : un palier demande un meilleur score ET un nombre de parties. Légende = quasi plafond + 400 parties.
insert into public.badge_tracks (game, tier, name, min_score, min_plays) values
  ('snake',0,'Recrue',5,1),('snake',1,'Argent',25,10),('snake',2,'Or',60,30),('snake',3,'Platine',120,80),('snake',4,'Diamant',220,200),('snake',5,'Légende',350,400),
  ('blocks',0,'Recrue',300,1),('blocks',1,'Argent',1500,10),('blocks',2,'Or',5000,30),('blocks',3,'Platine',12000,80),('blocks',4,'Diamant',25000,200),('blocks',5,'Légende',40000,400),
  ('space',0,'Recrue',200,1),('space',1,'Argent',1000,10),('space',2,'Or',3000,30),('space',3,'Platine',7000,80),('space',4,'Diamant',12000,200),('space',5,'Légende',18000,400),
  ('boyblocks',0,'Recrue',100,1),('boyblocks',1,'Argent',600,10),('boyblocks',2,'Or',2000,30),('boyblocks',3,'Platine',6000,80),('boyblocks',4,'Diamant',15000,200),('boyblocks',5,'Légende',40000,400)
on conflict (game, tier) do update set name = excluded.name, min_score = excluded.min_score, min_plays = excluded.min_plays;

create table if not exists public.user_tiers (
  user_id uuid not null references auth.users(id) on delete cascade,
  game text not null, tier int not null check (tier between 0 and 5),
  unlocked_at timestamptz not null default now(),
  primary key (user_id, game, tier)
);
alter table public.user_tiers enable row level security;
drop policy if exists "je lis mes paliers" on public.user_tiers;
create policy "je lis mes paliers" on public.user_tiers for select using (auth.uid() = user_id);
revoke insert, update, delete, truncate on public.user_tiers from anon, authenticated;

alter table public.profiles add column if not exists favorites text[] not null default '{}';

-- Calcule les paliers mérités (à partir des scores déjà enregistrés), les enregistre, renvoie les NOUVEAUX.
-- Un palier débloqué n'est jamais retiré. Les paliers inférieurs sont débloqués en même temps.
create or replace function public.sync_tiers() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); fresh jsonb;
begin
  perform public.guard_action(uid);
  with st as (select game, max(score) best, count(*) plays from public.scores where user_id = uid group by game),
  earned as (
    select t.game, t.tier, t.name from public.badge_tracks t join st on st.game = t.game
     where st.best >= t.min_score and st.plays >= t.min_plays
  ),
  ins as (
    insert into public.user_tiers (user_id, game, tier)
    select uid, e.game, e.tier from earned e on conflict do nothing returning game, tier
  )
  select coalesce(jsonb_agg(jsonb_build_object('game', i.game, 'tier', i.tier, 'name', t.name) order by i.game, i.tier), '[]'::jsonb)
    into fresh from ins i join public.badge_tracks t on t.game = i.game and t.tier = i.tier;
  return fresh;
end $$;

-- Ma progression : par jeu, meilleur score, parties, palier atteint, prochain palier et ce qu'il demande.
create or replace function public.my_tiers() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid();
begin
  perform public.guard_action(uid);
  return jsonb_build_object(
    'favorites', coalesce((select favorites from public.profiles where id = uid), '{}'),
    'games', coalesce((
      select jsonb_agg(jsonb_build_object(
        'game', g.game, 'best', coalesce(st.best, 0), 'plays', coalesce(st.plays, 0),
        'tier', (select max(ut.tier) from public.user_tiers ut where ut.user_id = uid and ut.game = g.game),
        'next', (select jsonb_build_object('tier', t.tier, 'name', t.name, 'min_score', t.min_score, 'min_plays', t.min_plays)
                   from public.badge_tracks t where t.game = g.game
                    and t.tier = coalesce((select max(ut.tier) + 1 from public.user_tiers ut where ut.user_id = uid and ut.game = g.game), 0))
      ) order by g.game)
      from (select distinct game from public.badge_tracks) g
      left join (select game, max(score) best, count(*) plays from public.scores where user_id = uid group by game) st on st.game = g.game
    ), '[]'::jsonb));
end $$;

-- 3 badges favoris au maximum, uniquement des paliers déjà débloqués (format "jeu:palier", ex. "snake:2").
create or replace function public.set_favorites(p_list text[]) returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); x text; clean text[] := '{}'; g text; t int;
begin
  perform public.guard_action(uid);
  if p_list is null then p_list := '{}'; end if;
  if array_length(p_list, 1) > 3 then raise exception 'too many favorites'; end if;
  foreach x in array p_list loop
    if x !~ '^[a-z]{3,12}:[0-5]$' then raise exception 'invalid favorite'; end if;
    g := split_part(x, ':', 1); t := split_part(x, ':', 2)::int;
    if not exists (select 1 from public.user_tiers where user_id = uid and game = g and tier = t) then raise exception 'not unlocked'; end if;
    if not (x = any (clean)) then clean := clean || x; end if;
  end loop;
  update public.profiles set favorites = clean where id = uid;
end $$;

-- Fiche d'un joueur : mêmes règles que public_profile (soi-même ou ami ; bloqué = inconnu).
create or replace function public.public_tiers(p_pseudo text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); other uuid;
begin
  perform public.guard_action(uid);
  other := public.uid_of(p_pseudo);
  if other is null or public.is_blocked_between(uid, other) then raise exception 'unknown player'; end if;
  if other <> uid and not public.are_friends(uid, other) then return jsonb_build_object('favorites', '[]'::jsonb, 'games', '[]'::jsonb); end if;
  return jsonb_build_object(
    'favorites', coalesce((select to_jsonb(p.favorites) from public.profiles p where p.id = other), '[]'::jsonb),
    'games', coalesce((select jsonb_agg(jsonb_build_object('game', ut.game, 'tier', ut.tier) order by ut.game)
                         from (select game, max(tier) tier from public.user_tiers where user_id = other group by game) ut), '[]'::jsonb));
end $$;

revoke all on function public.sync_tiers(), public.my_tiers(), public.set_favorites(text[]), public.public_tiers(text) from public, anon;
grant execute on function public.sync_tiers(), public.my_tiers(), public.set_favorites(text[]), public.public_tiers(text) to authenticated;

-- BOYGAMES schema v10 — BoyBlocks « règles 2 » (tirage stratégique en solo). Voir schema_v10_boyblocks_regles2.sql.
alter table public.boyblocks_runs add column if not exists rules int not null default 1;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'boyblocks_runs_rules_check') then
    alter table public.boyblocks_runs add constraint boyblocks_runs_rules_check check (rules in (1, 2));
  end if;
end $$;

-- Un lot « au hasard » pour un essai donné (même tirage que dans bb_deal).
create or replace function public.bb_raw(seed bigint, idx int, salt int, shwt int[], total int)
returns int[] language plpgsql immutable as $$
declare st bigint; v double precision; p int[3]; col int[3]; k int; x double precision; j int;
begin
  st := public.bb_mix(seed, idx, salt);
  for k in 1 .. 3 loop
    select o_a, o_v into st, v from public.bb_step(st);
    x := v * total; p[k] := array_length(shwt, 1) - 1;
    for j in 1 .. array_length(shwt, 1) loop
      x := x - shwt[j];
      if x < 0 then p[k] := j - 1; exit; end if;
    end loop;
  end loop;
  for k in 1 .. 3 loop
    select o_a, o_v into st, v from public.bb_step(st);
    col[k] := 1 + floor(v * 7)::int;
  end loop;
  return array[p[1], p[2], p[3], col[1], col[2], col[3]];
end $$;

-- Note d'un lot (miroir de tripleQuality) : pièces posables, lignes complétables, combo possible.
create or replace function public.bb_quality(grid int[], shp int[], shn int[], shh int[], shw int[], t int[])
returns int language plpgsql immutable as $$
declare re int[] := array_fill(0, array[8]); ce int[] := array_fill(0, array[8]);
  rown int[]; coln int[]; q int := 0; clearing int := 0; k int; i int; id int; r int; c int; dr int; dc int;
  fitsn int; best int; lines int;
begin
  for r in 0 .. 7 loop
    for c in 0 .. 7 loop
      if grid[r * 8 + c + 1] = 0 then re[r + 1] := re[r + 1] + 1; ce[c + 1] := ce[c + 1] + 1; end if;
    end loop;
  end loop;
  for k in 1 .. 3 loop
    id := t[k];
    rown := array_fill(0, array[5]); coln := array_fill(0, array[5]);
    for i in 0 .. shn[id + 1] - 1 loop
      rown[shp[id + 1][2 * i + 1] + 1] := rown[shp[id + 1][2 * i + 1] + 1] + 1;
      coln[shp[id + 1][2 * i + 2] + 1] := coln[shp[id + 1][2 * i + 2] + 1] + 1;
    end loop;
    fitsn := 0; best := 0;
    for r in 0 .. 8 - shh[id + 1] loop
      for c in 0 .. 8 - shw[id + 1] loop
        if public.bb_fits(grid, shp, shn, id, r, c) then
          fitsn := fitsn + 1; lines := 0;
          for dr in 0 .. shh[id + 1] - 1 loop if re[r + dr + 1] = rown[dr + 1] then lines := lines + 1; end if; end loop;
          for dc in 0 .. shw[id + 1] - 1 loop if ce[c + dc + 1] = coln[dc + 1] then lines := lines + 1; end if; end loop;
          if lines > best then best := lines; end if;
        end if;
      end loop;
    end loop;
    q := q + case when fitsn = 0 then -30 else 10 + least(fitsn, 3) end + 12 * best;
    if best > 0 then clearing := clearing + 1; end if;
  end loop;
  if clearing >= 2 then q := q + 8; end if;
  return q;
end $$;

-- Tirage stratégique (miroir de dealStrategic) : 70 % meilleur des 4 lots, 30 % tirage au hasard.
create or replace function public.bb_deal2(seed bigint, idx int, grid int[], shp int[], shn int[], shh int[], shw int[], shwt int[], total int)
returns int[] language plpgsql immutable as $$
declare st bigint; v double precision; salt int; t int[]; q int; best int[]; bestq int;
begin
  st := public.bb_mix(seed, idx, 97);
  select o_v into v from public.bb_step(st);
  if floor(v * 100)::int >= 70 then
    return public.bb_deal(seed, idx, grid, true, shp, shn, shh, shw, shwt, total);
  end if;
  for salt in 0 .. 3 loop
    t := public.bb_raw(seed, idx, salt, shwt, total);
    q := public.bb_quality(grid, shp, shn, shh, shw, t);
    if best is null or q > bestq then best := t; bestq := q; end if;
  end loop;
  return best;
end $$;

-- Rejeu complet avec choix des règles (1 = au hasard, 2 = stratégique en solo).
create or replace function public.bb_replay2(p_seed bigint, p_moves jsonb, p_ensure boolean, p_rules int)
returns table (ok boolean, err text, at int, score int, moves int, lines int, best_streak int, over boolean)
language plpgsql stable as $$
declare
  shwt int[]; shn int[]; shh int[]; shw int[]; shp int[]; total int;
  grid int[] := array_fill(0, array[64]);
  pc int[]; g_score int := 0; streak int := 0; best int := 0; nlines int := 0; nmoves int := 0; idx int := 0; is_over boolean;
  i int; m jsonb; slot int; r int; c int; id int; k int; rr int; cc int; n int; gain int; clr int;
  rows_full boolean[]; cols_full boolean[]; any_left boolean; mult numeric; strategic boolean := p_ensure and p_rules = 2;
begin
  select array_agg(weight order by s.id), array_agg(s.n order by s.id), array_agg(h order by s.id), array_agg(w order by s.id), array_agg(cells order by s.id), sum(weight)::int
    into shwt, shn, shh, shw, shp, total from public.bb_shapes s;
  if p_moves is null or jsonb_typeof(p_moves) <> 'array' or jsonb_array_length(p_moves) > 3000 then
    return query select false, 'moves', 0, 0, 0, 0, 0, false; return;
  end if;
  if strategic then pc := public.bb_deal2(p_seed, 0, grid, shp, shn, shh, shw, shwt, total);
  else pc := public.bb_deal(p_seed, 0, grid, p_ensure, shp, shn, shh, shw, shwt, total); end if;
  is_over := not (public.bb_can(grid, shp, shn, shh, shw, pc[1]) or public.bb_can(grid, shp, shn, shh, shw, pc[2]) or public.bb_can(grid, shp, shn, shh, shw, pc[3]));
  for i in 0 .. jsonb_array_length(p_moves) - 1 loop
    if is_over then return query select false, 'over', i, g_score, nmoves, nlines, best, is_over; return; end if;
    m := p_moves -> i;
    if jsonb_typeof(m) <> 'array' or jsonb_array_length(m) <> 3
       or (m ->> 0) !~ '^[0-9]+$' or (m ->> 1) !~ '^-?[0-9]+$' or (m ->> 2) !~ '^-?[0-9]+$' then
      return query select false, 'pos', i, g_score, nmoves, nlines, best, is_over; return;
    end if;
    slot := (m ->> 0)::int; r := (m ->> 1)::int; c := (m ->> 2)::int;
    if slot > 2 or pc[slot + 1] < 0 then return query select false, 'slot', i, g_score, nmoves, nlines, best, is_over; return; end if;
    id := pc[slot + 1];
    if not public.bb_fits(grid, shp, shn, id, r, c) then return query select false, 'fit', i, g_score, nmoves, nlines, best, is_over; return; end if;
    clr := pc[4 + slot];
    for k in 0 .. shn[id + 1] - 1 loop
      grid[(r + shp[id + 1][2 * k + 1]) * 8 + (c + shp[id + 1][2 * k + 2]) + 1] := clr;
    end loop;
    gain := shn[id + 1];
    rows_full := array_fill(true, array[8]); cols_full := array_fill(true, array[8]); n := 0;
    for rr in 0 .. 7 loop
      for cc in 0 .. 7 loop
        if grid[rr * 8 + cc + 1] = 0 then rows_full[rr + 1] := false; cols_full[cc + 1] := false; end if;
      end loop;
    end loop;
    for rr in 1 .. 8 loop
      if rows_full[rr] then n := n + 1; end if;
      if cols_full[rr] then n := n + 1; end if;
    end loop;
    if n > 0 then
      for rr in 0 .. 7 loop
        for cc in 0 .. 7 loop
          if rows_full[rr + 1] or cols_full[cc + 1] then grid[rr * 8 + cc + 1] := 0; end if;
        end loop;
      end loop;
      streak := streak + 1;
      if streak > best then best := streak; end if;
      mult := least(4, 1 + 0.5 * (streak - 1));
      gain := gain + floor(5 * n * (n + 1) * mult + 0.5)::int;
      nlines := nlines + n;
      any_left := false;
      for k in 1 .. 64 loop if grid[k] <> 0 then any_left := true; exit; end if; end loop;
      if not any_left then gain := gain + 300; end if;
    else
      streak := 0;
    end if;
    g_score := g_score + gain; nmoves := nmoves + 1;
    pc[slot + 1] := -1;
    if pc[1] < 0 and pc[2] < 0 and pc[3] < 0 then
      idx := idx + 1;
      if strategic then pc := public.bb_deal2(p_seed, idx, grid, shp, shn, shh, shw, shwt, total);
      else pc := public.bb_deal(p_seed, idx, grid, p_ensure, shp, shn, shh, shw, shwt, total); end if;
    end if;
    is_over := not ((pc[1] >= 0 and public.bb_can(grid, shp, shn, shh, shw, pc[1])) or (pc[2] >= 0 and public.bb_can(grid, shp, shn, shh, shw, pc[2])) or (pc[3] >= 0 and public.bb_can(grid, shp, shn, shh, shw, pc[3])));
  end loop;
  return query select true, null::text, null::int, g_score, nmoves, nlines, best, is_over;
end $$;

-- Nouvelle partie « règles 2 ». boyblocks_start() reste disponible (règles 1) pour les anciennes versions du site.
create or replace function public.boyblocks_start_v2() returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); rid uuid; s bigint;
begin
  perform public.guard_action(uid);
  if (select count(*) from public.boyblocks_runs where user_id = uid and finished_at is null and started_at > now() - interval '1 hour') >= 12 then
    raise exception 'too many runs';
  end if;
  s := floor(random() * 4294967296)::bigint;
  insert into public.boyblocks_runs (user_id, seed, rules) values (uid, s, 2) returning id into rid;
  return jsonb_build_object('run_id', rid, 'seed', s, 'rules', 2);
end $$;

-- Fin de partie : rejoue avec les règles de la partie (1 ou 2).
create or replace function public.boyblocks_finish(p_run uuid, p_moves jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); run public.boyblocks_runs; res record; aw jsonb; secs numeric;
begin
  perform public.guard_action(uid);
  select * into run from public.boyblocks_runs where id = p_run and user_id = uid for update;
  if not found or run.finished_at is not null then raise exception 'invalid run'; end if;
  if run.started_at < now() - interval '6 hours' then raise exception 'run expired'; end if;
  select * into res from public.bb_replay2(run.seed, p_moves, true, coalesce(run.rules, 1));
  if not res.ok or res.moves < 1 then raise exception 'invalid run'; end if;
  secs := extract(epoch from (now() - run.started_at));
  if secs < res.moves * 0.2 then raise exception 'invalid run'; end if;       -- impossible de jouer aussi vite
  if res.score > 2000000 then raise exception 'invalid score'; end if;
  update public.boyblocks_runs set finished_at = now(), score = res.score, moves = res.moves where id = p_run;
  aw := public.bb_award(uid, res.score);
  return aw || jsonb_build_object('score', res.score, 'lines', res.lines, 'moves', res.moves, 'best_streak', res.best_streak, 'over', res.over, 'rules', coalesce(run.rules, 1));
end $$;

-- droits : fonctions internes inaccessibles, deux fonctions de jeu ouvertes aux joueurs connectés
revoke all on function public.bb_raw(bigint, int, int, int[], int), public.bb_quality(int[], int[], int[], int[], int[], int[]),
  public.bb_deal2(bigint, int, int[], int[], int[], int[], int[], int[], int),
  public.bb_replay2(bigint, jsonb, boolean, int) from public, anon, authenticated;
revoke all on function public.boyblocks_start_v2(), public.boyblocks_finish(uuid, jsonb) from public, anon;
grant execute on function public.boyblocks_start_v2(), public.boyblocks_finish(uuid, jsonb) to authenticated;

-- BOYGAMES schema v11 — réglages de l'économie BOYCOINS (valeurs d'origine). Voir schema_v11_economie_reglages.sql.
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

-- BOYGAMES schema v12 — préparation monétisation (tout désactivé). Voir schema_v12_monetisation.sql.
-- ============ Réglages (tout désactivé) ============
create table if not exists public.monetization_settings (
  key text primary key, value jsonb not null, updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);
alter table public.monetization_settings enable row level security;
revoke all on public.monetization_settings from anon, authenticated;
insert into public.monetization_settings (key, value) values
  ('ads', '{"enabled": false, "provider": "test", "slots": {"home": true, "scores": true, "shop": false}}'),
  ('rewarded', '{"enabled": false, "continue_max": 1, "daily_max": 10, "games": ["snake", "space"], "bc_per_continue": 0}'),
  ('premium', '{"enabled": false, "price_eur": 0.99, "pioneer_limit": 100}')
on conflict (key) do nothing;

create or replace function public.monet(p_key text) returns jsonb language sql stable security definer set search_path = public as $$
  select value from public.monetization_settings where key = p_key;
$$;

-- ============ Tables ============
create table if not exists public.premium_subscriptions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  status text not null check (status in ('active', 'canceled', 'expired')),
  source text not null default 'test' check (source in ('test', 'stripe', 'apple', 'google')),
  started_at timestamptz not null default now(),
  current_period_end timestamptz not null,
  canceled_at timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.premium_subscriptions enable row level security;
drop policy if exists "je vois mon abonnement" on public.premium_subscriptions;
create policy "je vois mon abonnement" on public.premium_subscriptions for select using (auth.uid() = user_id);
revoke insert, update, delete, truncate on public.premium_subscriptions from anon, authenticated;

create table if not exists public.scores_continued (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  game text not null, score int not null check (score >= 0), continues int not null check (continues between 1 and 5),
  created_at timestamptz not null default now()
);
alter table public.scores_continued enable row level security;
drop policy if exists "je lis mes parties continuees" on public.scores_continued;
create policy "je lis mes parties continuees" on public.scores_continued for select using (auth.uid() = user_id);
revoke insert, update, delete, truncate on public.scores_continued from anon, authenticated;

create table if not exists public.ad_events (
  id bigint generated always as identity primary key,
  user_id uuid references auth.users(id) on delete set null,
  kind text not null check (kind in ('rewarded_continue')),
  game text not null default '', created_at timestamptz not null default now()
);
create index if not exists ad_events_user_day on public.ad_events (user_id, created_at);
alter table public.ad_events enable row level security;
revoke all on public.ad_events from anon, authenticated;

-- cosmétiques réservés aux Premium (achetables en BC seulement avec un abonnement actif)
alter table public.shop_items add column if not exists premium_only boolean not null default false;

-- badge à vie « Pionnier Premium » (exclusif : protégé par le trigger des badges exclusifs, jamais retiré)
insert into public.badges (code, name, description, sort, exclusive) values
 ('premium_pioneer', 'PIONNIER PREMIUM', 'Un des premiers abonnés BOYGAMES Premium. Conservé à vie, même après résiliation.', 102, true)
on conflict (code) do update set name = excluded.name, description = excluded.description, exclusive = true;

-- ============ Premium ============
create or replace function public.is_premium(p_uid uuid) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.premium_subscriptions where user_id = p_uid and status in ('active', 'canceled') and current_period_end > now());
$$;

create or replace function public.me()
returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'pseudo', p.pseudo, 'country', p.country, 'avatar', p.avatar, 'featured_badge', p.featured_badge,
    'xp', s.xp, 'level', s.level,
    'level_start_xp', 50 * (s.level - 1) * (s.level - 1),
    'next_level_xp', 50 * s.level * s.level,
    'bc', s.bc,
    'badges', coalesce((select jsonb_agg(ub.badge_code order by ub.earned_at) from public.user_badges ub where ub.user_id = p.id), '[]'::jsonb),
    'items', coalesce((select jsonb_agg(jsonb_build_object('code', ui.item_code, 'equipped', ui.equipped)) from public.user_items ui where ui.user_id = p.id), '[]'::jsonb),
    'streak', coalesce((select ls.streak from public.login_streaks ls where ls.user_id = p.id), 0),
    'daily_claimed_today', coalesce((select ls.last_claim = (now() at time zone 'Europe/Paris')::date from public.login_streaks ls where ls.user_id = p.id), false),
    'premium', public.is_premium(p.id),
    'premium_until', (select ps.current_period_end from public.premium_subscriptions ps where ps.user_id = p.id and public.is_premium(p.id))
  )
  from public.profiles p join public.player_stats s on s.user_id = p.id
  where p.id = auth.uid();
$$;

create or replace function public.public_profile(p_pseudo text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  uid uuid := auth.uid(); other uuid; rel text; full_view boolean;
  p public.profiles; s public.player_stats; fb jsonb; tt jsonb;
begin
  perform public.guard_action(uid);
  other := public.uid_of(p_pseudo);
  if other is null or public.is_blocked_between(uid, other) then raise exception 'unknown player'; end if;
  select * into p from public.profiles where id = other;
  select * into s from public.player_stats where user_id = other;
  rel := case
    when other = uid then 'self'
    when public.are_friends(uid, other) then 'friend'
    when exists (select 1 from public.friendships f where f.user_a = least(uid, other) and f.user_b = greatest(uid, other)) then 'pending'
    else 'none' end;
  full_view := rel in ('self', 'friend');
  select jsonb_build_object('code', b.code, 'name', b.name) into fb
    from public.badges b join public.user_badges ub on ub.badge_code = b.code
   where ub.user_id = other and b.code = p.featured_badge;
  select jsonb_build_object('code', si.code, 'name', si.name) into tt
    from public.user_items ui join public.shop_items si on si.code = ui.item_code
   where ui.user_id = other and ui.equipped and si.kind = 'title' limit 1;
  return jsonb_build_object(
    'pseudo', p.pseudo, 'avatar', p.avatar, 'level', coalesce(s.level, 1),
    'relation', rel, 'featured_badge', fb, 'title', tt,
    'member_since', p.created_at,
    'premium', public.is_premium(other),
    'xp', case when full_view then coalesce(s.xp, 0) end,
    'level_start_xp', 50 * (coalesce(s.level,1) - 1) * (coalesce(s.level,1) - 1),
    'next_level_xp', 50 * coalesce(s.level,1) * coalesce(s.level,1),
    'badges', case when full_view then coalesce((select jsonb_agg(ub.badge_code order by ub.earned_at)
                    from public.user_badges ub where ub.user_id = other), '[]'::jsonb) end,
    'games', case when full_view then coalesce((select jsonb_agg(jsonb_build_object('game', g.game, 'best', g.best, 'plays', g.plays) order by g.game)
                    from (select game, max(score) best, count(*) plays from public.scores where user_id = other group by game) g), '[]'::jsonb) end);
end $$;

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
  if item.premium_only and not public.is_premium(uid) then raise exception 'premium only'; end if;
  if exists (select 1 from public.user_items where user_id = uid and item_code = p_code) then
    raise exception 'already owned';
  end if;

  update public.player_stats set bc = bc - item.price where user_id = uid and bc >= item.price;
  if not found then raise exception 'not enough coins'; end if;

  insert into public.bc_ledger (user_id, delta, reason) values (uid, -item.price, 'shop:' || p_code);
  insert into public.user_items (user_id, item_code) values (uid, p_code);
end;
$$;

-- ============ Continuation par vidéo (solo) ============
-- Appelée avant d'afficher la vidéo : vérifie le réglage, le jeu et la limite quotidienne, et trace l'événement.
create or replace function public.rewarded_continue(p_game text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r jsonb := public.monet('rewarded'); n int;
begin
  perform public.guard_action(uid);
  if r is null or not coalesce((r ->> 'enabled')::boolean, false) then raise exception 'rewarded disabled'; end if;
  if not (r -> 'games') ? p_game then raise exception 'game not eligible'; end if;
  select count(*) into n from public.ad_events where user_id = uid and kind = 'rewarded_continue'
     and created_at > (date_trunc('day', now() at time zone 'Europe/Paris') at time zone 'Europe/Paris');
  if n >= coalesce((r ->> 'daily_max')::int, 10) then raise exception 'daily limit'; end if;
  insert into public.ad_events (user_id, kind, game) values (uid, 'rewarded_continue', p_game);
  return jsonb_build_object('ok', true, 'remaining_today', coalesce((r ->> 'daily_max')::int, 10) - n - 1,
                            'skip_ad', public.is_premium(uid));
end $$;

-- Score final d'une partie continuée : hors classement, hors records, hors missions et paliers.
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

-- ============ Ce que le site lit (visiteurs compris) ============
create or replace function public.monetization_public() returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'ads', public.monet('ads'),
    'rewarded', (select r - 'daily_max' - 'bc_per_continue' from (select public.monet('rewarded') r) x),
    'premium', public.monet('premium') || jsonb_build_object('pioneer_left',
        greatest(0, coalesce((public.monet('premium') ->> 'pioneer_limit')::int, 0) - (select count(*) from public.user_badges where badge_code = 'premium_pioneer'))));
$$;

-- ============ Administration ============
create or replace function public.staff_monetization() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  return jsonb_build_object(
    'settings', (select jsonb_object_agg(key, value) from public.monetization_settings),
    'premium', coalesce((select jsonb_agg(jsonb_build_object('pseudo', public.pseudo_of(ps.user_id), 'status', ps.status, 'source', ps.source,
                 'until', ps.current_period_end, 'active', public.is_premium(ps.user_id)) order by ps.started_at) from public.premium_subscriptions ps), '[]'::jsonb),
    'stats', jsonb_build_object(
      'videos_today', (select count(*) from public.ad_events where created_at > (date_trunc('day', now() at time zone 'Europe/Paris') at time zone 'Europe/Paris')),
      'videos_total', (select count(*) from public.ad_events),
      'continued_games', (select count(*) from public.scores_continued),
      'pioneers', (select count(*) from public.user_badges where badge_code = 'premium_pioneer')));
end $$;

create or replace function public.staff_monetization_set(p_key text, p_value jsonb) returns void language plpgsql security definer set search_path = public as $$
declare old jsonb; g text;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  select value into old from public.monetization_settings where key = p_key;
  if not found then raise exception 'unknown setting'; end if;
  if jsonb_typeof(p_value) <> 'object' or jsonb_typeof(p_value -> 'enabled') <> 'boolean' then raise exception 'invalid value'; end if;
  if p_key = 'ads' then
    if (p_value ->> 'provider') not in ('test', 'adsense') or jsonb_typeof(p_value -> 'slots') <> 'object' then raise exception 'invalid value'; end if;
    if exists (select 1 from jsonb_each(p_value -> 'slots') e where e.key not in ('home', 'scores', 'shop') or jsonb_typeof(e.value) <> 'boolean') then raise exception 'invalid slot'; end if;
  elsif p_key = 'rewarded' then
    if (p_value ->> 'continue_max')::int not between 0 and 2 or (p_value ->> 'daily_max')::int not between 0 and 50
       or (p_value ->> 'bc_per_continue')::int not between 0 and 5 or jsonb_typeof(p_value -> 'games') <> 'array' then raise exception 'invalid value'; end if;
    for g in select jsonb_array_elements_text(p_value -> 'games') loop
      if g not in ('snake', 'space') then raise exception 'invalid game'; end if;      -- jeux qui savent continuer
    end loop;
  elsif p_key = 'premium' then
    if (p_value ->> 'price_eur')::numeric not between 0 and 50 or (p_value ->> 'pioneer_limit')::int not between 0 and 100000 then raise exception 'invalid value'; end if;
  end if;
  update public.monetization_settings set value = p_value, updated_at = now(), updated_by = auth.uid() where key = p_key;
  insert into public.economy_log (by_user, what, old_value, new_value) values (auth.uid(), 'monetisation:' || p_key, old, p_value);
end $$;

-- Simulation d'abonnement (source « test ») : p_days > 0 active ou prolonge, 0 résilie (fin immédiate).
-- Le badge « Pionnier Premium » est donné à l'activation tant que la limite n'est pas atteinte ; il n'est jamais retiré.
create or replace function public.staff_premium_set(p_pseudo text, p_days int) returns jsonb language plpgsql security definer set search_path = public as $$
declare who uuid; lim int; holders int; old jsonb;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  who := public.uid_of(p_pseudo);
  if who is null then raise exception 'unknown player'; end if;
  if p_days is null or p_days not between 0 and 400 then raise exception 'invalid days'; end if;
  select to_jsonb(ps) into old from public.premium_subscriptions ps where user_id = who;
  if p_days = 0 then
    update public.premium_subscriptions set status = 'expired', current_period_end = now(), canceled_at = now(), updated_at = now() where user_id = who;
  else
    insert into public.premium_subscriptions (user_id, status, source, current_period_end)
    values (who, 'active', 'test', now() + make_interval(days => p_days))
    on conflict (user_id) do update set status = 'active', canceled_at = null, updated_at = now(),
      current_period_end = greatest(public.premium_subscriptions.current_period_end, now()) + make_interval(days => p_days);
    perform pg_advisory_xact_lock(60602);
    lim := coalesce((public.monet('premium') ->> 'pioneer_limit')::int, 0);
    select count(*) into holders from public.user_badges where badge_code = 'premium_pioneer';
    if holders < lim then insert into public.user_badges (user_id, badge_code) values (who, 'premium_pioneer') on conflict do nothing; end if;
  end if;
  insert into public.economy_log (by_user, what, old_value, new_value)
  values (auth.uid(), 'premium:' || p_pseudo, old, (select to_jsonb(ps) from public.premium_subscriptions ps where user_id = who));
  return jsonb_build_object('premium', public.is_premium(who), 'pioneer', exists (select 1 from public.user_badges where user_id = who and badge_code = 'premium_pioneer'));
end $$;

-- ============ Droits ============
revoke all on function public.monet(text), public.is_premium(uuid) from public, anon, authenticated;
revoke all on function public.me(), public.public_profile(text), public.buy_item(text), public.rewarded_continue(text),
  public.submit_continued_score(text, int, int), public.monetization_public(), public.staff_monetization(),
  public.staff_monetization_set(text, jsonb), public.staff_premium_set(text, int) from public, anon;
grant execute on function public.me(), public.public_profile(text), public.buy_item(text), public.rewarded_continue(text),
  public.submit_continued_score(text, int, int), public.monetization_public(), public.staff_monetization(),
  public.staff_monetization_set(text, jsonb), public.staff_premium_set(text, int) to authenticated;
grant execute on function public.monetization_public() to anon;

-- BOYGAMES schema v13 — file de validation marketing. Voir schema_v13_marketing.sql.
-- ============ Tables ============
create table if not exists public.marketing_videos (
  id uuid primary key default gen_random_uuid(),
  run_id text not null unique,                                   -- identifiant du passage GitHub : jamais deux fois la même vidéo
  created_at timestamptz not null default now(),
  game text not null default 'boyblocks',
  video_path text not null,                                      -- chemin dans le bucket privé « marketing »
  poster_path text,
  duration numeric,
  stats jsonb not null default '{}'::jsonb,
  accroche text not null default '' check (char_length(accroche) <= 80),
  legende text not null default '' check (char_length(legende) <= 2200),
  hashtags text[] not null default '{}',
  text_source text not null default '',
  status text not null default 'a_valider' check (status in ('a_valider', 'validee', 'refusee', 'publiee', 'erreur')),
  scheduled_for timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null,
  reviewed_at timestamptz,
  note text not null default '' check (char_length(note) <= 500)
);
create index if not exists marketing_videos_status on public.marketing_videos (status, created_at desc);
alter table public.marketing_videos enable row level security;
revoke all on public.marketing_videos from anon, authenticated;

-- une ligne par vidéo et par réseau : empêche les publications en double, garde l'historique et les erreurs
create table if not exists public.marketing_posts (
  video_id uuid not null references public.marketing_videos(id) on delete cascade,
  platform text not null check (platform in ('youtube', 'instagram', 'tiktok')),
  status text not null default 'en_attente' check (status in ('en_attente', 'publie', 'erreur', 'manuel')),
  attempts int not null default 0,
  last_error text not null default '',
  external_id text,
  published_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (video_id, platform)
);
alter table public.marketing_posts enable row level security;
revoke all on public.marketing_posts from anon, authenticated;

create table if not exists public.marketing_settings (key text primary key, value jsonb not null, updated_at timestamptz not null default now());
alter table public.marketing_settings enable row level security;
revoke all on public.marketing_settings from anon, authenticated;
insert into public.marketing_settings (key, value) values
  ('auto', '{"enabled": false, "per_day": 1, "platforms": ["youtube", "instagram", "tiktok"], "hour": 18}')
on conflict (key) do nothing;

-- jeton de dépôt : seule son empreinte est gardée ici ; le jeton lui-même vit dans les secrets GitHub
create table if not exists public.marketing_ingest_keys (hash text primary key, created_at timestamptz not null default now(), label text not null default '');
alter table public.marketing_ingest_keys enable row level security;
revoke all on public.marketing_ingest_keys from anon, authenticated;

-- ============ Fonctions réservées à la fonction cloud (rôle service_role) ============
create or replace function public.marketing_token_ok(p_token text) returns boolean language sql stable security definer set search_path = public as $$
  select p_token is not null and char_length(p_token) >= 32
     and exists (select 1 from public.marketing_ingest_keys where hash = encode(sha256(convert_to(p_token, 'UTF8')), 'hex'));
$$;

create or replace function public.marketing_register(p_meta jsonb, p_video_path text, p_poster_path text) returns jsonb language plpgsql security definer set search_path = public as $$
declare v public.marketing_videos; tags text[];
begin
  if (select count(*) from public.marketing_videos where created_at > now() - interval '1 day') >= 10 then raise exception 'too many videos'; end if;
  select coalesce(array_agg(left(x, 40)), '{}') into tags from (select jsonb_array_elements_text(coalesce(p_meta -> 'textes' -> 'hashtags', '[]'::jsonb)) x limit 12) h;
  insert into public.marketing_videos (run_id, game, video_path, poster_path, duration, stats, accroche, legende, hashtags, text_source)
  values (left(p_meta ->> 'run_id', 80), coalesce(left(p_meta ->> 'game', 20), 'boyblocks'), p_video_path, p_poster_path,
          nullif(p_meta ->> 'duree', '')::numeric, coalesce(p_meta -> 'partie', '{}'::jsonb),
          left(coalesce(p_meta -> 'textes' ->> 'accroche', ''), 80), left(coalesce(p_meta -> 'textes' ->> 'legende', ''), 2200), tags,
          left(coalesce(p_meta -> 'textes' ->> 'source', ''), 40))
  on conflict (run_id) do nothing
  returning * into v;
  if v.id is null then return jsonb_build_object('ok', true, 'duplicate', true); end if;
  return jsonb_build_object('ok', true, 'id', v.id);
end $$;

-- ============ Administration (fondateur / admin) ============
create or replace function public.staff_marketing(p_status text default null) returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  return jsonb_build_object(
    'videos', coalesce((select jsonb_agg(to_jsonb(v) - 'reviewed_by' || jsonb_build_object('reviewer', public.pseudo_of(v.reviewed_by),
                 'posts', coalesce((select jsonb_agg(to_jsonb(p) - 'video_id') from public.marketing_posts p where p.video_id = v.id), '[]'::jsonb))
                 order by v.created_at desc)
               from (select * from public.marketing_videos where p_status is null or p_status = '' or status = p_status order by created_at desc limit 60) v), '[]'::jsonb),
    'counts', coalesce((select jsonb_object_agg(status, n) from (select status, count(*) n from public.marketing_videos group by status) c), '{}'::jsonb),
    'settings', (select jsonb_object_agg(key, value) from public.marketing_settings),
    'errors', coalesce((select jsonb_agg(jsonb_build_object('platform', platform, 'error', last_error, 'at', updated_at) order by updated_at desc)
               from (select * from public.marketing_posts where status = 'erreur' order by updated_at desc limit 20) e), '[]'::jsonb));
end $$;

-- Valider (avec date prévue) ou refuser une vidéo ; les textes peuvent être corrigés au passage.
create or replace function public.staff_marketing_review(p_id uuid, p_decision text, p_scheduled_for timestamptz default null,
  p_accroche text default null, p_legende text default null, p_hashtags text[] default null, p_note text default '') returns void
language plpgsql security definer set search_path = public as $$
declare v public.marketing_videos;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  if p_decision not in ('validee', 'refusee', 'a_valider') then raise exception 'invalid decision'; end if;
  select * into v from public.marketing_videos where id = p_id for update;
  if not found then raise exception 'unknown video'; end if;
  if v.status in ('publiee') then raise exception 'already published'; end if;
  update public.marketing_videos set status = p_decision, reviewed_by = auth.uid(), reviewed_at = now(),
    scheduled_for = case when p_decision = 'validee' then coalesce(p_scheduled_for, scheduled_for, now() + interval '1 day') else null end,
    accroche = coalesce(left(p_accroche, 80), accroche), legende = coalesce(left(p_legende, 2200), legende),
    hashtags = coalesce(p_hashtags[1:12], hashtags), note = left(coalesce(p_note, ''), 500)
  where id = p_id;
  if p_decision = 'validee' then
    insert into public.marketing_posts (video_id, platform)
    select p_id, x from jsonb_array_elements_text((select value -> 'platforms' from public.marketing_settings where key = 'auto')) x
    on conflict do nothing;
  end if;
end $$;

create or replace function public.staff_marketing_settings(p_value jsonb) returns void language plpgsql security definer set search_path = public as $$
declare x text;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  if jsonb_typeof(p_value -> 'enabled') <> 'boolean' or (p_value ->> 'per_day')::int not between 0 and 3
     or (p_value ->> 'hour')::int not between 0 and 23 or jsonb_typeof(p_value -> 'platforms') <> 'array' then raise exception 'invalid value'; end if;
  for x in select jsonb_array_elements_text(p_value -> 'platforms') loop
    if x not in ('youtube', 'instagram', 'tiktok') then raise exception 'invalid platform'; end if;
  end loop;
  update public.marketing_settings set value = p_value, updated_at = now() where key = 'auto';
  insert into public.economy_log (by_user, what, old_value, new_value) values (auth.uid(), 'marketing:auto', null, p_value);
end $$;

-- ============ Stockage privé des vidéos (Supabase Storage) ============
do $$ begin
  if to_regclass('storage.buckets') is not null then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('marketing', 'marketing', false, 52428800, array['video/mp4', 'image/jpeg'])
    on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
    -- lecture (aperçu) réservée à l'équipe ; aucun envoi ni suppression par le site
    execute 'drop policy if exists "marketing : lecture equipe" on storage.objects';
    -- v21 : rôle lu directement (public.is_admin() n'est pas exécutable par les joueurs connectés)
    execute 'create policy "marketing : lecture equipe" on storage.objects for select to authenticated using (bucket_id = ''marketing'' and exists (select 1 from public.user_roles r where r.user_id = auth.uid() and r.role in (''founder'', ''admin'')))';
  end if;
end $$;

-- ============ Droits ============
revoke all on function public.marketing_token_ok(text), public.marketing_register(jsonb, text, text) from public, anon, authenticated;
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'service_role') then
    execute 'grant execute on function public.marketing_token_ok(text), public.marketing_register(jsonb, text, text) to service_role';
  end if;
end $$;
revoke all on function public.staff_marketing(text), public.staff_marketing_review(uuid, text, timestamptz, text, text, text[], text),
  public.staff_marketing_settings(jsonb) from public, anon;
grant execute on function public.staff_marketing(text), public.staff_marketing_review(uuid, text, timestamptz, text, text, text[], text),
  public.staff_marketing_settings(jsonb) to authenticated;

-- BOYGAMES schema v14 — BoyBlocks 9x9 (essai). Voir schema_v14_boyblocks_9x9.sql.
-- ============ Données ============
alter table public.bb_shapes add column if not exists weight9 int;
update public.bb_shapes set weight9 = weight where weight9 is null;          -- 9x9 : mêmes fréquences (simulations du 15/10)
alter table public.boyblocks_runs add column if not exists size int not null default 8;
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'boyblocks_runs_size_check') then
    alter table public.boyblocks_runs add constraint boyblocks_runs_size_check check (size in (8, 9));
  end if;
end $$;

create table if not exists public.game_settings (key text primary key, value jsonb not null, updated_at timestamptz not null default now());
alter table public.game_settings enable row level security;
revoke all on public.game_settings from anon, authenticated;
insert into public.game_settings (key, value) values ('boyblocks9', '{"enabled": true}') on conflict (key) do nothing;

-- paliers du 9x9 : mêmes seuils que le 8x8, comptés à part
insert into public.badge_tracks (game, tier, name, min_score, min_plays) values
  ('boyblocks9',0,'Recrue',100,1),('boyblocks9',1,'Argent',600,10),('boyblocks9',2,'Or',2000,30),('boyblocks9',3,'Platine',6000,80),('boyblocks9',4,'Diamant',15000,200),('boyblocks9',5,'Légende',40000,400)
on conflict (game, tier) do nothing;

-- ============ Moteur généralisé (taille n = 8 ou 9) ============
create or replace function public.bb_fits_n(grid int[], shp int[], shn int[], id int, r int, c int, n int) returns boolean language plpgsql immutable as $$
declare i int; rr int; cc int;
begin
  for i in 0 .. shn[id + 1] - 1 loop
    rr := r + shp[id + 1][2 * i + 1]; cc := c + shp[id + 1][2 * i + 2];
    if rr < 0 or cc < 0 or rr >= n or cc >= n or grid[rr * n + cc + 1] <> 0 then return false; end if;
  end loop;
  return true;
end $$;

create or replace function public.bb_can_n(grid int[], shp int[], shn int[], shh int[], shw int[], id int, n int) returns boolean language plpgsql immutable as $$
declare r int; c int;
begin
  for r in 0 .. n - shh[id + 1] loop
    for c in 0 .. n - shw[id + 1] loop
      if public.bb_fits_n(grid, shp, shn, id, r, c, n) then return true; end if;
    end loop;
  end loop;
  return false;
end $$;

-- tirage « au hasard » (règles 1) : jusqu'à 12 essais si ensure, comme dealRandom
create or replace function public.bb_deal_n(seed bigint, idx int, grid int[], ensure boolean, shp int[], shn int[], shh int[], shw int[], shwt int[], total int, n int)
returns int[] language plpgsql immutable as $$
declare salt int; res int[];
begin
  for salt in 0 .. (case when ensure then 11 else 0 end) loop
    res := public.bb_raw(seed, idx, salt, shwt, total);
    if not ensure or public.bb_can_n(grid, shp, shn, shh, shw, res[1], n) or public.bb_can_n(grid, shp, shn, shh, shw, res[2], n)
       or public.bb_can_n(grid, shp, shn, shh, shw, res[3], n) then return res; end if;
  end loop;
  return res;
end $$;

create or replace function public.bb_quality_n(grid int[], shp int[], shn int[], shh int[], shw int[], t int[], n int)
returns int language plpgsql immutable as $$
declare re int[] := array_fill(0, array[n]); ce int[] := array_fill(0, array[n]);
  rown int[]; coln int[]; q int := 0; clearing int := 0; k int; i int; id int; r int; c int; dr int; dc int;
  fitsn int; best int; lines int;
begin
  for r in 0 .. n - 1 loop
    for c in 0 .. n - 1 loop
      if grid[r * n + c + 1] = 0 then re[r + 1] := re[r + 1] + 1; ce[c + 1] := ce[c + 1] + 1; end if;
    end loop;
  end loop;
  for k in 1 .. 3 loop
    id := t[k];
    rown := array_fill(0, array[5]); coln := array_fill(0, array[5]);
    for i in 0 .. shn[id + 1] - 1 loop
      rown[shp[id + 1][2 * i + 1] + 1] := rown[shp[id + 1][2 * i + 1] + 1] + 1;
      coln[shp[id + 1][2 * i + 2] + 1] := coln[shp[id + 1][2 * i + 2] + 1] + 1;
    end loop;
    fitsn := 0; best := 0;
    for r in 0 .. n - shh[id + 1] loop
      for c in 0 .. n - shw[id + 1] loop
        if public.bb_fits_n(grid, shp, shn, id, r, c, n) then
          fitsn := fitsn + 1; lines := 0;
          for dr in 0 .. shh[id + 1] - 1 loop if re[r + dr + 1] = rown[dr + 1] then lines := lines + 1; end if; end loop;
          for dc in 0 .. shw[id + 1] - 1 loop if ce[c + dc + 1] = coln[dc + 1] then lines := lines + 1; end if; end loop;
          if lines > best then best := lines; end if;
        end if;
      end loop;
    end loop;
    q := q + case when fitsn = 0 then -30 else 10 + least(fitsn, 3) end + 12 * best;
    if best > 0 then clearing := clearing + 1; end if;
  end loop;
  if clearing >= 2 then q := q + 8; end if;
  return q;
end $$;

create or replace function public.bb_deal2_n(seed bigint, idx int, grid int[], shp int[], shn int[], shh int[], shw int[], shwt int[], total int, n int)
returns int[] language plpgsql immutable as $$
declare st bigint; v double precision; salt int; t int[]; q int; best int[]; bestq int;
begin
  st := public.bb_mix(seed, idx, 97);
  select o_v into v from public.bb_step(st);
  if floor(v * 100)::int >= 70 then
    return public.bb_deal_n(seed, idx, grid, true, shp, shn, shh, shw, shwt, total, n);
  end if;
  for salt in 0 .. 3 loop
    t := public.bb_raw(seed, idx, salt, shwt, total);
    q := public.bb_quality_n(grid, shp, shn, shh, shw, t, n);
    if best is null or q > bestq then best := t; bestq := q; end if;
  end loop;
  return best;
end $$;

-- Rejeu complet, taille n : mêmes règles de score que le 8x8 (cases posées, lignes, combos, grille vidée)
create or replace function public.bb_replay_n(p_seed bigint, p_moves jsonb, p_ensure boolean, p_rules int, p_n int)
returns table (ok boolean, err text, at int, score int, moves int, lines int, best_streak int, over boolean)
language plpgsql stable as $$
declare
  sz int := case when p_n = 9 then 9 else 8 end;
  shwt int[]; shn int[]; shh int[]; shw int[]; shp int[]; total int;
  grid int[] := array_fill(0, array[sz * sz]);
  pc int[]; g_score int := 0; streak int := 0; best int := 0; nlines int := 0; nmoves int := 0; idx int := 0; is_over boolean;
  i int; m jsonb; slot int; r int; c int; id int; k int; rr int; cc int; nl int; gain int; clr int;
  rows_full boolean[]; cols_full boolean[]; any_left boolean; mult numeric; strategic boolean := p_ensure and p_rules = 2;
begin
  select array_agg(case when sz = 9 then s.weight9 else s.weight end order by s.id), array_agg(s.n order by s.id), array_agg(h order by s.id),
         array_agg(w order by s.id), array_agg(cells order by s.id), sum(case when sz = 9 then s.weight9 else s.weight end)::int
    into shwt, shn, shh, shw, shp, total from public.bb_shapes s;
  if p_moves is null or jsonb_typeof(p_moves) <> 'array' or jsonb_array_length(p_moves) > 3000 then
    return query select false, 'moves', 0, 0, 0, 0, 0, false; return;
  end if;
  if strategic then pc := public.bb_deal2_n(p_seed, 0, grid, shp, shn, shh, shw, shwt, total, sz);
  else pc := public.bb_deal_n(p_seed, 0, grid, p_ensure, shp, shn, shh, shw, shwt, total, sz); end if;
  is_over := not (public.bb_can_n(grid, shp, shn, shh, shw, pc[1], sz) or public.bb_can_n(grid, shp, shn, shh, shw, pc[2], sz) or public.bb_can_n(grid, shp, shn, shh, shw, pc[3], sz));
  for i in 0 .. jsonb_array_length(p_moves) - 1 loop
    if is_over then return query select false, 'over', i, g_score, nmoves, nlines, best, is_over; return; end if;
    m := p_moves -> i;
    if jsonb_typeof(m) <> 'array' or jsonb_array_length(m) <> 3
       or (m ->> 0) !~ '^[0-9]+$' or (m ->> 1) !~ '^-?[0-9]+$' or (m ->> 2) !~ '^-?[0-9]+$' then
      return query select false, 'pos', i, g_score, nmoves, nlines, best, is_over; return;
    end if;
    slot := (m ->> 0)::int; r := (m ->> 1)::int; c := (m ->> 2)::int;
    if slot > 2 or pc[slot + 1] < 0 then return query select false, 'slot', i, g_score, nmoves, nlines, best, is_over; return; end if;
    id := pc[slot + 1];
    if not public.bb_fits_n(grid, shp, shn, id, r, c, sz) then return query select false, 'fit', i, g_score, nmoves, nlines, best, is_over; return; end if;
    clr := pc[4 + slot];
    for k in 0 .. shn[id + 1] - 1 loop
      grid[(r + shp[id + 1][2 * k + 1]) * sz + (c + shp[id + 1][2 * k + 2]) + 1] := clr;
    end loop;
    gain := shn[id + 1];
    rows_full := array_fill(true, array[sz]); cols_full := array_fill(true, array[sz]); nl := 0;
    for rr in 0 .. sz - 1 loop
      for cc in 0 .. sz - 1 loop
        if grid[rr * sz + cc + 1] = 0 then rows_full[rr + 1] := false; cols_full[cc + 1] := false; end if;
      end loop;
    end loop;
    for rr in 1 .. sz loop
      if rows_full[rr] then nl := nl + 1; end if;
      if cols_full[rr] then nl := nl + 1; end if;
    end loop;
    if nl > 0 then
      for rr in 0 .. sz - 1 loop
        for cc in 0 .. sz - 1 loop
          if rows_full[rr + 1] or cols_full[cc + 1] then grid[rr * sz + cc + 1] := 0; end if;
        end loop;
      end loop;
      streak := streak + 1;
      if streak > best then best := streak; end if;
      mult := least(4, 1 + 0.5 * (streak - 1));
      gain := gain + floor(5 * nl * (nl + 1) * mult + 0.5)::int;
      nlines := nlines + nl;
      any_left := false;
      for k in 1 .. sz * sz loop if grid[k] <> 0 then any_left := true; exit; end if; end loop;
      if not any_left then gain := gain + 300; end if;
    else
      streak := 0;
    end if;
    g_score := g_score + gain; nmoves := nmoves + 1;
    pc[slot + 1] := -1;
    if pc[1] < 0 and pc[2] < 0 and pc[3] < 0 then
      idx := idx + 1;
      if strategic then pc := public.bb_deal2_n(p_seed, idx, grid, shp, shn, shh, shw, shwt, total, sz);
      else pc := public.bb_deal_n(p_seed, idx, grid, p_ensure, shp, shn, shh, shw, shwt, total, sz); end if;
    end if;
    is_over := not ((pc[1] >= 0 and public.bb_can_n(grid, shp, shn, shh, shw, pc[1], sz)) or (pc[2] >= 0 and public.bb_can_n(grid, shp, shn, shh, shw, pc[2], sz))
                 or (pc[3] >= 0 and public.bb_can_n(grid, shp, shn, shh, shw, pc[3], sz)));
  end loop;
  return query select true, null::text, null::int, g_score, nmoves, nlines, best, is_over;
end $$;

-- ============ Récompenses par jeu (« boyblocks » ou « boyblocks9 ») ============
create or replace function public.bb_award_game(p_uid uuid, p_score int, p_game text) returns jsonb language plpgsql security definer set search_path = public as $$
declare today date := (now() at time zone 'Europe/Paris')::date; xp_gain int; bc_gain int; earned_today int; before_level int; after_level int; badges text[];
begin
  if p_game not in ('boyblocks', 'boyblocks9') then raise exception 'unknown game'; end if;
  insert into public.player_stats (user_id) values (p_uid) on conflict do nothing;
  insert into public.scores (user_id, game, score) values (p_uid, p_game, p_score);
  xp_gain := 5 + least(p_score / 80, 60);
  bc_gain := public.bc_for_score('boyblocks', p_score);                    -- même barème de BC pour les deux grilles
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

-- ============ API joueurs ============
create or replace function public.game_settings_public() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_object_agg(key, value), '{}'::jsonb) from public.game_settings;
$$;

-- Nouvelle partie classée : taille 8 ou 9 (9 seulement si l'expérimentation est activée), tirage stratégique.
create or replace function public.boyblocks_start_v3(p_size int default 8) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); rid uuid; s bigint;
begin
  perform public.guard_action(uid);
  if p_size not in (8, 9) then raise exception 'invalid size'; end if;
  if p_size = 9 and not coalesce((select (value ->> 'enabled')::boolean from public.game_settings where key = 'boyblocks9'), false) then
    raise exception 'grid disabled';
  end if;
  if (select count(*) from public.boyblocks_runs where user_id = uid and finished_at is null and started_at > now() - interval '1 hour') >= 12 then
    raise exception 'too many runs';
  end if;
  s := floor(random() * 4294967296)::bigint;
  insert into public.boyblocks_runs (user_id, seed, rules, size) values (uid, s, 2, p_size) returning id into rid;
  return jsonb_build_object('run_id', rid, 'seed', s, 'rules', 2, 'size', p_size);
end $$;

-- Fin de partie : 8x8 vérifié exactement comme avant (bb_replay2) ; 9x9 par bb_replay_n, classé dans « boyblocks9 ».
create or replace function public.boyblocks_finish(p_run uuid, p_moves jsonb) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); run public.boyblocks_runs; res record; aw jsonb; secs numeric; nine boolean;
begin
  perform public.guard_action(uid);
  select * into run from public.boyblocks_runs where id = p_run and user_id = uid for update;
  if not found or run.finished_at is not null then raise exception 'invalid run'; end if;
  if run.started_at < now() - interval '6 hours' then raise exception 'run expired'; end if;
  nine := coalesce(run.size, 8) = 9;
  if nine then select * into res from public.bb_replay_n(run.seed, p_moves, true, coalesce(run.rules, 1), 9);
  else select * into res from public.bb_replay2(run.seed, p_moves, true, coalesce(run.rules, 1)); end if;
  if not res.ok or res.moves < 1 then raise exception 'invalid run'; end if;
  secs := extract(epoch from (now() - run.started_at));
  if secs < res.moves * 0.2 then raise exception 'invalid run'; end if;       -- impossible de jouer aussi vite
  if res.score > 2000000 then raise exception 'invalid score'; end if;
  update public.boyblocks_runs set finished_at = now(), score = res.score, moves = res.moves where id = p_run;
  aw := public.bb_award_game(uid, res.score, case when nine then 'boyblocks9' else 'boyblocks' end);
  return aw || jsonb_build_object('score', res.score, 'lines', res.lines, 'moves', res.moves, 'best_streak', res.best_streak, 'over', res.over,
                                  'rules', coalesce(run.rules, 1), 'size', coalesce(run.size, 8));
end $$;

-- favoris : autorise les identifiants de jeu avec chiffre (« boyblocks9 »)
create or replace function public.set_favorites(p_list text[]) returns void language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); x text; clean text[] := '{}'; g text; t int;
begin
  perform public.guard_action(uid);
  if p_list is null then p_list := '{}'; end if;
  if array_length(p_list, 1) > 3 then raise exception 'too many favorites'; end if;
  foreach x in array p_list loop
    if x !~ '^[a-z][a-z0-9]{2,11}:[0-5]$' then raise exception 'invalid favorite'; end if;
    g := split_part(x, ':', 1); t := split_part(x, ':', 2)::int;
    if not exists (select 1 from public.user_tiers where user_id = uid and game = g and tier = t) then raise exception 'not unlocked'; end if;
    if not (x = any (clean)) then clean := clean || x; end if;
  end loop;
  update public.profiles set favorites = clean where id = uid;
end $$;

-- Interrupteur de l'équipe : 9x9 activé / désactivé (retour au 8x8). Les scores 9x9 déjà faits sont conservés.
create or replace function public.staff_game_settings_set(p_key text, p_value jsonb) returns void language plpgsql security definer set search_path = public as $$
declare old jsonb;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  select value into old from public.game_settings where key = p_key;
  if not found then raise exception 'unknown setting'; end if;
  if jsonb_typeof(p_value) <> 'object' or jsonb_typeof(p_value -> 'enabled') <> 'boolean' then raise exception 'invalid value'; end if;
  update public.game_settings set value = p_value, updated_at = now() where key = p_key;
  insert into public.economy_log (by_user, what, old_value, new_value) values (auth.uid(), 'jeu:' || p_key, old, p_value);
end $$;

-- ============ Droits ============
revoke all on function public.bb_fits_n(int[], int[], int[], int, int, int, int), public.bb_can_n(int[], int[], int[], int[], int[], int, int),
  public.bb_deal_n(bigint, int, int[], boolean, int[], int[], int[], int[], int[], int, int),
  public.bb_quality_n(int[], int[], int[], int[], int[], int[], int),
  public.bb_deal2_n(bigint, int, int[], int[], int[], int[], int[], int[], int, int),
  public.bb_replay_n(bigint, jsonb, boolean, int, int), public.bb_award_game(uuid, int, text) from public, anon, authenticated;
revoke all on function public.boyblocks_start_v3(int), public.boyblocks_finish(uuid, jsonb), public.set_favorites(text[]),
  public.staff_game_settings_set(text, jsonb), public.game_settings_public() from public, anon;
grant execute on function public.boyblocks_start_v3(int), public.boyblocks_finish(uuid, jsonb), public.set_favorites(text[]),
  public.staff_game_settings_set(text, jsonb), public.game_settings_public() to authenticated;
grant execute on function public.game_settings_public() to anon;

-- BOYGAMES schema v15 — questionnaire des bêta-testeurs. Voir schema_v15_questionnaire.sql.
-- ============ Table ============
create table if not exists public.beta_survey (
  user_id uuid primary key references auth.users(id) on delete cascade,
  version int not null default 1,
  answers jsonb not null default '{}'::jsonb,        -- { "q_snake_speed": "parfaite", "q_tactile_pb": ["zoom", "defile"], ... }
  comment text not null default '' check (char_length(comment) <= 2000),
  completed_at timestamptz,                          -- null = brouillon (questionnaire pas encore envoyé)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  saves int not null default 0
);
alter table public.beta_survey enable row level security;
revoke all on public.beta_survey from anon, authenticated;

-- ============ Fonctions du site ============
-- Ses propres réponses (pour reprendre ou modifier).
create or replace function public.beta_survey_get() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); r public.beta_survey;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into r from public.beta_survey where user_id = uid;
  if not found then return null; end if;
  return jsonb_build_object('version', r.version, 'answers', r.answers, 'comment', r.comment,
    'completed_at', r.completed_at, 'updated_at', r.updated_at);
end $$;

-- Enregistre (ou remplace) ses réponses. p_complete = true quand le testeur appuie sur « Envoyer ».
-- Contrôles : identifiants courts (lettres, chiffres, _), choix simple ou liste de 10 choix au plus.
create or replace function public.beta_survey_save(p_answers jsonb, p_comment text default '', p_complete boolean default false, p_version int default 1)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); k text; v jsonb; x jsonb; c text := trim(coalesce(p_comment, '')); r public.beta_survey;
begin
  perform public.guard_action(uid);
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then raise exception 'invalid answers'; end if;
  if (select count(*) from jsonb_object_keys(p_answers)) > 60 then raise exception 'invalid answers'; end if;
  if p_version is null or p_version not between 1 and 99 then raise exception 'invalid version'; end if;
  if char_length(c) > 2000 then raise exception 'comment too long'; end if;
  for k, v in select * from jsonb_each(p_answers) loop
    if k !~ '^[a-z][a-z0-9_]{1,23}$' then raise exception 'invalid answers'; end if;
    if jsonb_typeof(v) = 'string' then
      if (v #>> '{}') !~ '^[a-z0-9_]{1,24}$' then raise exception 'invalid answers'; end if;
    elsif jsonb_typeof(v) = 'array' then
      if jsonb_array_length(v) > 10 then raise exception 'invalid answers'; end if;
      for x in select * from jsonb_array_elements(v) loop
        if jsonb_typeof(x) <> 'string' or (x #>> '{}') !~ '^[a-z0-9_]{1,24}$' then raise exception 'invalid answers'; end if;
      end loop;
    elsif jsonb_typeof(v) <> 'null' then raise exception 'invalid answers';
    end if;
  end loop;
  insert into public.beta_survey as s (user_id, version, answers, comment, completed_at, saves)
  values (uid, p_version, p_answers, c, case when p_complete then now() end, 1)
  on conflict (user_id) do update set version = excluded.version, answers = excluded.answers, comment = excluded.comment,
    completed_at = case when p_complete then now() else s.completed_at end, updated_at = now(), saves = s.saves + 1
  returning * into r;
  return jsonb_build_object('ok', true, 'completed_at', r.completed_at, 'updated_at', r.updated_at);
end $$;

-- ============ Administration (équipe) ============
-- Toutes les réponses, avec le pseudo du testeur. Les statistiques sont calculées par la page « Retours bêta ».
create or replace function public.staff_beta_survey() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff() then raise exception 'forbidden'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('pseudo', coalesce(public.pseudo_of(s.user_id), '?'), 'version', s.version,
      'answers', s.answers, 'comment', s.comment, 'completed_at', s.completed_at, 'updated_at', s.updated_at) order by s.updated_at desc)
    from public.beta_survey s), '[]'::jsonb);
end $$;

-- ============ Droits ============
revoke all on function public.beta_survey_get(), public.beta_survey_save(jsonb, text, boolean, int), public.staff_beta_survey() from public, anon;
grant execute on function public.beta_survey_get(), public.beta_survey_save(jsonb, text, boolean, int), public.staff_beta_survey() to authenticated;

-- BOYGAMES schema v16 — espace bêta-testeur, missions, badge sur validation. Voir schema_v16_espace_beta.sql.
-- ============ Données ============
insert into public.app_settings (key, value) values ('beta_missions', '{"version": 1,
  "codes": ["compte", "snake", "boyblocks", "space", "multi", "amis", "boybot", "classements", "progression", "mobile", "questionnaire"],
  "required": ["compte", "snake", "boyblocks", "space", "multi", "amis", "boybot", "classements", "progression", "mobile", "questionnaire"]}')
on conflict (key) do nothing;

insert into public.badges (code, name, description, sort, exclusive) values
 ('beta_tester', 'BÊTA-TESTEUR BOYGAMES', 'A réellement participé à la bêta : missions remplies, questionnaire envoyé, validé par l''équipe. Badge permanent.', 102, true)
on conflict (code) do nothing;                                            -- ne remplace jamais un badge existant

create table if not exists public.beta_missions (
  user_id uuid not null references auth.users(id) on delete cascade,
  version int not null,
  code text not null check (code ~ '^[a-z][a-z0-9_]{1,23}$'),
  status text not null check (status in ('non_teste', 'reussi', 'probleme', 'impossible')),
  note text not null default '' check (char_length(note) <= 500),
  updated_at timestamptz not null default now(),
  primary key (user_id, version, code)
);
alter table public.beta_missions enable row level security;
revoke all on public.beta_missions from anon, authenticated;

-- décisions de l'équipe sur le badge (historique : qui, quand, pourquoi)
create table if not exists public.beta_validations (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  decision text not null check (decision in ('valide', 'a_revoir')),
  note text not null default '' check (char_length(note) <= 500),
  by_user uuid references auth.users(id) on delete set null,
  at timestamptz not null default now()
);
alter table public.beta_validations enable row level security;
revoke all on public.beta_validations from anon, authenticated;

-- ============ Fonctions internes ============
create or replace function public.beta_cfg() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select value from public.app_settings where key = 'beta_missions'), '{"version": 1, "codes": [], "required": []}'::jsonb);
$$;

-- Preuves déjà présentes en base (affichées à titre d'indice, jamais transformées en validation automatique).
create or replace function public.beta_evidence(p_uid uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'compte', exists (select 1 from public.profiles where id = p_uid),
    'snake', (select count(*) from public.scores where user_id = p_uid and game = 'snake'),
    'boyblocks', (select count(*) from public.scores where user_id = p_uid and game in ('boyblocks', 'boyblocks9')),
    'space', (select count(*) from public.scores where user_id = p_uid and game = 'space'),
    'amis', (select count(*) from public.friendships where status = 'accepted' and p_uid in (user_a, user_b)),
    'classements', (select count(*) from public.scores where user_id = p_uid),
    'progression', (select jsonb_build_object('xp', coalesce(max(xp), 0), 'niveau', coalesce(max(level), 1), 'bc', coalesce(max(bc), 0),
                      'badges', (select count(*) from public.user_badges where user_id = p_uid)) from public.player_stats where user_id = p_uid),
    'questionnaire', (select completed_at is not null from public.beta_survey where user_id = p_uid));
$$;

-- Éligible au badge : toutes les missions obligatoires remplies (réussi, problème ou impossible) + questionnaire envoyé.
create or replace function public.beta_eligible(p_uid uuid) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select completed_at is not null from public.beta_survey where user_id = p_uid), false)
     and not exists (
       select 1 from jsonb_array_elements_text(public.beta_cfg() -> 'required') req(code)
       where not exists (select 1 from public.beta_missions m where m.user_id = p_uid and m.version = (public.beta_cfg() ->> 'version')::int
                           and m.code = req.code and m.status <> 'non_teste'));
$$;

-- ============ Fonctions du site (testeur) ============
create or replace function public.beta_space() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); cfg jsonb := public.beta_cfg();
begin
  perform public.guard_action(uid);
  return jsonb_build_object('version', (cfg ->> 'version')::int, 'codes', cfg -> 'codes', 'required', cfg -> 'required',
    'missions', coalesce((select jsonb_object_agg(code, jsonb_build_object('status', status, 'note', note, 'updated_at', updated_at))
                 from public.beta_missions where user_id = uid and version = (cfg ->> 'version')::int), '{}'::jsonb),
    'evidence', public.beta_evidence(uid),
    'eligible', public.beta_eligible(uid),
    'badge', exists (select 1 from public.user_badges where user_id = uid and badge_code = 'beta_tester'),
    'bugs', (select count(*) from public.bug_reports where user_id = uid));
end $$;

create or replace function public.beta_mission_set(p_code text, p_status text, p_note text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); cfg jsonb := public.beta_cfg();
begin
  perform public.guard_action(uid);
  if p_code is null or not (cfg -> 'codes') ? p_code then raise exception 'unknown mission'; end if;
  if p_status not in ('non_teste', 'reussi', 'probleme', 'impossible') then raise exception 'invalid status'; end if;
  if char_length(coalesce(p_note, '')) > 500 then raise exception 'note too long'; end if;
  insert into public.beta_missions (user_id, version, code, status, note) values (uid, (cfg ->> 'version')::int, p_code, p_status, trim(coalesce(p_note, '')))
  on conflict (user_id, version, code) do update set status = excluded.status, note = excluded.note, updated_at = now();
  return jsonb_build_object('ok', true, 'eligible', public.beta_eligible(uid));
end $$;

-- ============ Équipe : suivi bêta ============
-- Testeurs = membres de la bêta + tous ceux qui ont rempli une mission ou le questionnaire. Aucune donnée privée (pas d'e-mail).
create or replace function public.staff_beta_overview() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare cfg jsonb := public.beta_cfg(); v int := (public.beta_cfg() ->> 'version')::int;
begin
  if not public.is_staff() then raise exception 'forbidden'; end if;
  return jsonb_build_object('version', v, 'codes', cfg -> 'codes', 'required', cfg -> 'required',
    'beta_on', coalesce((select (value ->> 'on')::boolean from public.app_settings where key = 'beta'), false),
    'testers', coalesce((select jsonb_agg(t order by t ->> 'pseudo') from (
      select jsonb_build_object('pseudo', p.pseudo, 'member', exists (select 1 from public.beta_members b where b.user_id = u.id),
        'missions', coalesce((select jsonb_object_agg(m.code, m.status) from public.beta_missions m where m.user_id = u.id and m.version = v), '{}'::jsonb),
        'notes', coalesce((select jsonb_object_agg(m.code, m.note) from public.beta_missions m where m.user_id = u.id and m.version = v and m.note <> ''), '{}'::jsonb),
        'last_update', (select max(updated_at) from public.beta_missions m where m.user_id = u.id),
        'survey', (select completed_at from public.beta_survey s where s.user_id = u.id),
        'survey_draft', exists (select 1 from public.beta_survey s where s.user_id = u.id and s.completed_at is null),
        'bugs', (select count(*) from public.bug_reports r where r.user_id = u.id),
        'evidence', public.beta_evidence(u.id), 'eligible', public.beta_eligible(u.id),
        'badge', exists (select 1 from public.user_badges ub where ub.user_id = u.id and ub.badge_code = 'beta_tester'),
        'decision', (select jsonb_build_object('decision', d.decision, 'note', d.note, 'at', d.at, 'by', public.pseudo_of(d.by_user))
                     from public.beta_validations d where d.user_id = u.id order by d.at desc limit 1)) t
      from (select user_id id from public.beta_members union select user_id from public.beta_missions union select user_id from public.beta_survey) u
      join public.profiles p on p.id = u.id) x), '[]'::jsonb));
end $$;

-- Validation finale du badge (fondateur / admin). « valide » exige l'éligibilité ; « a_revoir » note simplement la décision.
create or replace function public.staff_beta_validate(p_pseudo text, p_decision text, p_note text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare target uuid := public.uid_of(p_pseudo); added int := 0;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  if target is null then raise exception 'unknown player'; end if;
  if p_decision not in ('valide', 'a_revoir') then raise exception 'invalid decision'; end if;
  if p_decision = 'valide' then
    if not public.beta_eligible(target) then raise exception 'not eligible'; end if;
    insert into public.user_badges (user_id, badge_code) values (target, 'beta_tester') on conflict do nothing;
    get diagnostics added = row_count;
    if added > 0 then perform public.notify(target, 'badge', 'Badge BÊTA-TESTEUR BOYGAMES obtenu. Merci pour ta participation !'); end if;
  end if;
  insert into public.beta_validations (user_id, decision, note, by_user) values (target, p_decision, left(coalesce(p_note, ''), 500), auth.uid());
  return jsonb_build_object('ok', true, 'badge_added', added > 0);
end $$;

-- Nouvelle manche de missions après une mise à jour (les réponses de la manche précédente sont conservées).
create or replace function public.staff_beta_new_round() returns int language plpgsql security definer set search_path = public as $$
declare nv int;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  nv := (public.beta_cfg() ->> 'version')::int + 1;
  update public.app_settings set value = jsonb_set(value, '{version}', to_jsonb(nv)) where key = 'beta_missions';
  insert into public.economy_log (by_user, what, old_value, new_value) values (auth.uid(), 'beta:missions_round', to_jsonb(nv - 1), to_jsonb(nv));
  return nv;
end $$;

-- ============ Droits ============
revoke all on function public.beta_cfg(), public.beta_evidence(uuid), public.beta_eligible(uuid) from public, anon, authenticated;
revoke all on function public.beta_space(), public.beta_mission_set(text, text, text), public.staff_beta_overview(),
  public.staff_beta_validate(text, text, text), public.staff_beta_new_round() from public, anon;
grant execute on function public.beta_space(), public.beta_mission_set(text, text, text), public.staff_beta_overview(),
  public.staff_beta_validate(text, text, text), public.staff_beta_new_round() to authenticated;

-- BOYGAMES schema v18 — invitations bêta par lien ou code. Voir schema_v18_invitations.sql.
-- ============ Tables ============
create table if not exists public.beta_invites (
  code text primary key check (code ~ '^[A-Z2-9]{8}$'),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  max_uses int not null default 1 check (max_uses between 1 and 50),
  uses int not null default 0 check (uses >= 0),
  note text not null default '' check (char_length(note) <= 80),
  revoked boolean not null default false
);
alter table public.beta_invites enable row level security;
revoke all on public.beta_invites from anon, authenticated;

create table if not exists public.beta_invite_uses (
  code text not null references public.beta_invites(code) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  used_at timestamptz not null default now(),
  primary key (code, user_id)
);
alter table public.beta_invite_uses enable row level security;
revoke all on public.beta_invite_uses from anon, authenticated;

-- essais ratés (contre la devinette de codes) : 10 par heure au plus
create table if not exists public.beta_invite_fails (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  at timestamptz not null default now()
);
create index if not exists beta_invite_fails_user on public.beta_invite_fails (user_id, at desc);
alter table public.beta_invite_fails enable row level security;
revoke all on public.beta_invite_fails from anon, authenticated;

-- ============ Joueur : utiliser un code ============
-- Retour : {ok, status} avec status = 'joined' (admis), 'already' (déjà admis), 'invalid', 'expired', 'used', 'too_many'.
-- Les refus ne lèvent pas d'erreur : l'essai raté doit être enregistré (anti-devinette).
create or replace function public.beta_redeem(p_code text) returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); c text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g')); inv public.beta_invites;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if public.is_banned(uid) then raise exception 'banned'; end if;
  if public.is_staff(uid) or exists (select 1 from public.beta_members where user_id = uid) then
    return jsonb_build_object('ok', true, 'status', 'already');
  end if;
  if (select count(*) from public.beta_invite_fails where user_id = uid and at > now() - interval '1 hour') >= 10 then
    return jsonb_build_object('ok', false, 'status', 'too_many');
  end if;
  select * into inv from public.beta_invites where code = c for update;
  if not found or inv.revoked then
    insert into public.beta_invite_fails (user_id) values (uid);
    return jsonb_build_object('ok', false, 'status', 'invalid');
  end if;
  if inv.expires_at < now() then return jsonb_build_object('ok', false, 'status', 'expired'); end if;
  if inv.uses >= inv.max_uses then return jsonb_build_object('ok', false, 'status', 'used'); end if;
  insert into public.beta_invite_uses (code, user_id) values (c, uid) on conflict do nothing;
  update public.beta_invites set uses = uses + 1 where code = c;
  insert into public.beta_members (user_id) values (uid) on conflict do nothing;   -- déclencheurs existants inchangés
  perform public.notify(uid, 'beta', 'Bienvenue dans la bêta de BOYGAMES !');
  return jsonb_build_object('ok', true, 'status', 'joined');
end $$;

-- ============ Équipe : créer, lister, révoquer ============
create or replace function public.staff_beta_invite_create(p_max_uses int default 1, p_days int default 14, p_note text default '')
returns jsonb language plpgsql security definer set search_path = public as $$
declare alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; c text; i int; b bytea;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  if p_max_uses is null or p_max_uses not between 1 and 50 or p_days is null or p_days not between 1 and 90 then raise exception 'invalid value'; end if;
  loop
    -- 8 octets aléatoires : les 4 premiers octets de deux UUID v4 (aléatoires ; gen_random_uuid est intégré à Postgres)
    b := substring(uuid_send(gen_random_uuid()) from 1 for 4) || substring(uuid_send(gen_random_uuid()) from 1 for 4); c := '';
    for i in 0..7 loop c := c || substr(alphabet, 1 + (get_byte(b, i) % 32), 1); end loop;
    exit when not exists (select 1 from public.beta_invites where code = c);
  end loop;
  insert into public.beta_invites (code, created_by, expires_at, max_uses, note)
  values (c, auth.uid(), now() + make_interval(days => p_days), p_max_uses, left(trim(coalesce(p_note, '')), 80));
  return jsonb_build_object('code', c, 'expires_at', now() + make_interval(days => p_days), 'max_uses', p_max_uses);
end $$;

create or replace function public.staff_beta_invites() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('code', i.code, 'note', i.note, 'created_at', i.created_at, 'expires_at', i.expires_at,
      'max_uses', i.max_uses, 'uses', i.uses, 'revoked', i.revoked, 'by', public.pseudo_of(i.created_by),
      'players', coalesce((select jsonb_agg(coalesce(public.pseudo_of(u.user_id), '(sans profil)') order by u.used_at) from public.beta_invite_uses u where u.code = i.code), '[]'::jsonb))
    order by i.created_at desc) from (select * from public.beta_invites order by created_at desc limit 100) i), '[]'::jsonb);
end $$;

create or replace function public.staff_beta_invite_revoke(p_code text) returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  update public.beta_invites set revoked = true where code = upper(p_code);
  if not found then raise exception 'unknown invite'; end if;
end $$;

-- ============ Droits ============
revoke all on function public.beta_redeem(text), public.staff_beta_invite_create(int, int, text), public.staff_beta_invites(),
  public.staff_beta_invite_revoke(text) from public, anon;
grant execute on function public.beta_redeem(text), public.staff_beta_invite_create(int, int, text), public.staff_beta_invites(),
  public.staff_beta_invite_revoke(text) to authenticated;

-- BOYGAMES schema v19 — liste complète des joueurs pour l'équipe. Voir schema_v19_liste_joueurs.sql.
create or replace function public.staff_players() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff() then raise exception 'forbidden'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'pseudo', p.pseudo, 'country', p.country, 'created_at', p.created_at,
      'last_sign_in', u.last_sign_in_at, 'confirmed', u.email_confirmed_at is not null,
      'level', coalesce(s.level, 1), 'xp', coalesce(s.xp, 0), 'bc', coalesce(s.bc, 0),
      'games', (select count(*) from public.scores sc where sc.user_id = p.id),
      'last_game', (select max(created_at) from public.scores sc where sc.user_id = p.id),
      'beta', exists (select 1 from public.beta_members b where b.user_id = p.id),
      'role', (select r.role from public.user_roles r where r.user_id = p.id),
      'banned', exists (select 1 from public.bans x where x.user_id = p.id and (x.until is null or x.until > now())),
      'badges', (select coalesce(jsonb_agg(ub.badge_code order by ub.badge_code), '[]'::jsonb) from public.user_badges ub where ub.user_id = p.id))
    order by p.created_at desc)
    from public.profiles p join auth.users u on u.id = p.id left join public.player_stats s on s.user_id = p.id), '[]'::jsonb);
end $$;
revoke all on function public.staff_players() from public, anon;
grant execute on function public.staff_players() to authenticated;

-- BOYGAMES schema v20 — fiche administrative + journal des interventions. Voir schema_v20_fiche_joueur.sql.
-- ============ Journal des interventions ============
create table if not exists public.admin_actions (
  id bigint generated always as identity primary key,
  at timestamptz not null default now(),
  by_user uuid references auth.users(id) on delete set null,     -- null = automatique (migration, système)
  target_user uuid references auth.users(id) on delete cascade,
  action text not null,
  detail jsonb not null default '{}'::jsonb
);
create index if not exists admin_actions_target on public.admin_actions (target_user, at desc);
alter table public.admin_actions enable row level security;
revoke all on public.admin_actions from anon, authenticated;

create or replace function public.trg_admin_log() returns trigger language plpgsql security definer set search_path = public as $$
declare tgt uuid; act text; det jsonb := '{}'::jsonb;
begin
  if tg_table_name = 'bans' then
    tgt := coalesce(new.user_id, old.user_id);
    if tg_op = 'DELETE' then act := 'reactivation';
    else act := 'suspension'; det := jsonb_build_object('motif', new.reason, 'jusqu_au', new.until); end if;
  elsif tg_table_name = 'beta_members' then
    tgt := coalesce(new.user_id, old.user_id); act := case when tg_op = 'DELETE' then 'beta_retrait' else 'beta_ajout' end;
  elsif tg_table_name = 'user_roles' then
    tgt := coalesce(new.user_id, old.user_id); act := 'role';
    det := jsonb_build_object('avant', case when tg_op = 'INSERT' then null else old.role end, 'apres', case when tg_op = 'DELETE' then null else new.role end);
  elsif tg_table_name = 'beta_validations' then
    tgt := new.user_id; act := 'badge_beta_tester_' || new.decision; det := jsonb_build_object('note', new.note);
  elsif tg_table_name = 'reports' then
    if new.status is not distinct from old.status then return null; end if;
    tgt := new.reported_id; act := 'signalement_' || new.status; det := jsonb_build_object('signalement', new.id);
  elsif tg_table_name = 'user_badges' then
    if not coalesce((select exclusive from public.badges where code = new.badge_code), false) then return null; end if;
    tgt := new.user_id; act := 'badge_exclusif'; det := jsonb_build_object('badge', new.badge_code);
  else
    return null;
  end if;
  if exists (select 1 from auth.users where id = tgt) then
    insert into public.admin_actions (by_user, target_user, action, detail) values (auth.uid(), tgt, act, det);
  end if;
  return null;
end $$;
revoke all on function public.trg_admin_log() from public, anon, authenticated;

drop trigger if exists admin_log on public.bans;
create trigger admin_log after insert or update or delete on public.bans for each row execute function public.trg_admin_log();
drop trigger if exists admin_log on public.beta_members;
create trigger admin_log after insert or delete on public.beta_members for each row execute function public.trg_admin_log();
drop trigger if exists admin_log on public.user_roles;
create trigger admin_log after insert or update or delete on public.user_roles for each row execute function public.trg_admin_log();
drop trigger if exists admin_log on public.beta_validations;
create trigger admin_log after insert on public.beta_validations for each row execute function public.trg_admin_log();
drop trigger if exists admin_log on public.reports;
create trigger admin_log after update on public.reports for each row execute function public.trg_admin_log();
drop trigger if exists admin_log on public.user_badges;
create trigger admin_log after insert on public.user_badges for each row execute function public.trg_admin_log();

-- ============ Fiche administrative d'un joueur ============
create or replace function public.staff_player_detail(p_pseudo text) returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := public.uid_of(p_pseudo); v int := (public.beta_cfg() ->> 'version')::int;
begin
  if not public.is_staff() then raise exception 'forbidden'; end if;
  if uid is null then raise exception 'unknown player'; end if;
  return jsonb_build_object(
    'profile', (select jsonb_build_object('pseudo', p.pseudo, 'avatar', p.avatar, 'country', p.country, 'created_at', p.created_at,
                  'featured_badge', p.featured_badge, 'favorites', p.favorites) from public.profiles p where p.id = uid),
    'account', (select jsonb_build_object('last_sign_in', u.last_sign_in_at, 'confirmed', u.email_confirmed_at is not null) from auth.users u where u.id = uid),
    'stats', (select jsonb_build_object('level', s.level, 'xp', s.xp, 'bc', s.bc) from public.player_stats s where s.user_id = uid),
    'role', (select role from public.user_roles where user_id = uid),
    'ban', (select jsonb_build_object('reason', reason, 'since', banned_at, 'until', until) from public.bans where user_id = uid and (until is null or until > now())),
    'badges', coalesce((select jsonb_agg(jsonb_build_object('code', ub.badge_code, 'name', b.name, 'exclusive', b.exclusive, 'at', ub.earned_at) order by ub.earned_at)
                 from public.user_badges ub join public.badges b on b.code = ub.badge_code where ub.user_id = uid), '[]'::jsonb),
    'records', coalesce((select jsonb_agg(jsonb_build_object('game', game, 'best', best, 'plays', plays, 'last', last) order by game)
                 from (select game, max(score) best, count(*) plays, max(created_at) last from public.scores where user_id = uid group by game) r), '[]'::jsonb),
    'continued', (select count(*) from public.scores_continued where user_id = uid),
    'friends', (select count(*) from public.friendships where status = 'accepted' and uid in (user_a, user_b)),
    'beta', jsonb_build_object(
       'member', exists (select 1 from public.beta_members where user_id = uid),
       'since', (select added_at from public.beta_members where user_id = uid),
       'invite', (select code from public.beta_invite_uses where user_id = uid order by used_at limit 1),
       'version', v, 'codes', public.beta_cfg() -> 'codes',
       'missions', coalesce((select jsonb_object_agg(code, jsonb_build_object('status', status, 'note', note)) from public.beta_missions where user_id = uid and version = v), '{}'::jsonb),
       'survey', (select completed_at from public.beta_survey where user_id = uid),
       'survey_draft', exists (select 1 from public.beta_survey where user_id = uid and completed_at is null),
       'eligible', public.beta_eligible(uid)),
    'reports_received', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'at', r.created_at, 'by', public.pseudo_of(r.reporter_id), 'reason', r.reason, 'status', r.status) order by r.created_at desc)
                 from (select * from public.reports where reported_id = uid order by created_at desc limit 30) r), '[]'::jsonb),
    'reports_sent', (select count(*) from public.reports where reporter_id = uid),
    'bugs', coalesce((select jsonb_agg(jsonb_build_object('id', b.id, 'at', b.created_at, 'category', b.category, 'status', b.status, 'text', left(b.description, 160)) order by b.created_at desc)
                 from (select * from public.bug_reports where user_id = uid order by created_at desc limit 20) b), '[]'::jsonb),
    'history', coalesce((select jsonb_agg(jsonb_build_object('at', a.at, 'action', a.action, 'by', coalesce(public.pseudo_of(a.by_user), 'système'), 'self', a.by_user = uid, 'detail', a.detail) order by a.at desc)
                 from (select * from public.admin_actions where target_user = uid order by at desc limit 50) a), '[]'::jsonb));
end $$;
revoke all on function public.staff_player_detail(text) from public, anon;
grant execute on function public.staff_player_detail(text) to authenticated;

-- BOYGAMES schema v22 — ticket de partie et vraisemblance des scores solo. Voir schema_v22_tickets_partie.sql.
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

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

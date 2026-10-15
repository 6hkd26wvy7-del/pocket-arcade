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

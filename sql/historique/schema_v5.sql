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

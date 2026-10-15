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

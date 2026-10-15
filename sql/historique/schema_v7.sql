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

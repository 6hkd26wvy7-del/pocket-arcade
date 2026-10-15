-- BOYGAMES — MIGRATION v13 : file de validation des vidéos marketing (TEST)
-- À lancer APRÈS la v12. Tout-ou-rien, relançable. Ne touche à aucune donnée existante.
-- Les vidéos fabriquées chaque jour (GitHub Actions) sont déposées dans un stockage PRIVÉ (bucket « marketing ») par la
-- fonction cloud « marketing-ingest », puis attendent une validation humaine dans l'administration. RIEN n'est publié.
begin;

do $$ begin
  if to_regclass('public.monetization_settings') is null then
    raise exception 'PRE-CONTROLE : la migration v12 doit être lancée AVANT celle-ci. Rien n''a été modifié.';
  end if;
end $$;

do $$
begin
  perform set_config('boygames.mig_tx', txid_current()::text, true);
  perform set_config('boygames.mig_before', (jsonb_build_object(
    'profiles', (select count(*) from public.profiles), 'scores', (select count(*) from public.scores),
    'bc_ledger', (select count(*) from public.bc_ledger), 'user_badges', (select count(*) from public.user_badges),
    'sum_bc', (select coalesce(sum(bc), 0) from public.player_stats)))::text, true);
end $$;
do $$
begin
  if coalesce(current_setting('boygames.mig_tx', true), '') <> txid_current()::text
     or coalesce(current_setting('boygames.mig_before', true), '') = '' then
    raise exception 'EXECUTION EN PLUSIEURS MORCEAUX : ce script doit etre lance en entier, d''un seul bloc. Rien n''a ete modifie.';
  end if;
end $$;

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
    execute 'create policy "marketing : lecture equipe" on storage.objects for select to authenticated using (bucket_id = ''marketing'' and public.is_admin())';
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

-- ============ Contrôles ============
do $$
declare b jsonb; a jsonb := jsonb_build_object(
    'profiles', (select count(*) from public.profiles), 'scores', (select count(*) from public.scores),
    'bc_ledger', (select count(*) from public.bc_ledger), 'user_badges', (select count(*) from public.user_badges),
    'sum_bc', (select coalesce(sum(bc), 0) from public.player_stats));
begin
  if coalesce(current_setting('boygames.mig_tx', true), '') <> txid_current()::text then
    raise exception 'EXECUTION EN PLUSIEURS MORCEAUX : relancer le script en entier, d''un seul bloc.';
  end if;
  b := current_setting('boygames.mig_before')::jsonb;
  if a is distinct from b then raise exception 'GARDE-FOU : des donnees existantes auraient change (% -> %). Rien n''a ete applique.', b, a; end if;
  if has_function_privilege('anon', 'public.marketing_register(jsonb,text,text)', 'execute')
     or has_function_privilege('authenticated', 'public.marketing_register(jsonb,text,text)', 'execute')
     or has_function_privilege('authenticated', 'public.marketing_token_ok(text)', 'execute')
     or has_function_privilege('anon', 'public.staff_marketing(text)', 'execute')
     or has_table_privilege('authenticated', 'public.marketing_videos', 'select')
     or has_table_privilege('anon', 'public.marketing_ingest_keys', 'select') then
    raise exception 'GARDE-FOU DROITS : permissions inattendues. Rien n''a été appliqué.';
  end if;
end $$;

commit;

select 'Migration v13 appliquée (file marketing, rien de publié)' as resultat,
  (select count(*) from public.marketing_videos) as videos, (select value from public.marketing_settings where key = 'auto') as mode_auto;

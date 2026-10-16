-- BOYGAMES — MIGRATION v18 : invitations bêta par lien ou code (TEST)
-- À lancer APRÈS la v17. Tout-ou-rien, relançable. Ne touche à aucune donnée existante.
-- L'équipe crée un code (1 ou plusieurs usages, durée limitée) ; le testeur ouvre le lien …/?invite=CODE ou tape le code
-- dans son profil ; dès qu'il est connecté, il devient membre de la bêta. Les règles existantes s'appliquent telles
-- quelles (ex. badge ÉDITION FONDATRICE pour les 10 premiers membres, via le déclencheur déjà en place).
begin;

do $$ begin
  if to_regclass('public.beta_missions') is null then
    raise exception 'PRE-CONTROLE : les migrations v16 et v17 doivent être lancées AVANT celle-ci. Rien n''a été modifié.';
  end if;
end $$;

do $$
begin
  perform set_config('boygames.mig_tx', txid_current()::text, true);
  perform set_config('boygames.mig_before', (jsonb_build_object(
    'profiles', (select count(*) from public.profiles), 'scores', (select count(*) from public.scores),
    'beta_members', (select count(*) from public.beta_members), 'user_badges', (select count(*) from public.user_badges),
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

-- ============ Contrôles ============
do $$
declare b jsonb; a jsonb := jsonb_build_object(
    'profiles', (select count(*) from public.profiles), 'scores', (select count(*) from public.scores),
    'beta_members', (select count(*) from public.beta_members), 'user_badges', (select count(*) from public.user_badges),
    'sum_bc', (select coalesce(sum(bc), 0) from public.player_stats));
begin
  if coalesce(current_setting('boygames.mig_tx', true), '') <> txid_current()::text then
    raise exception 'EXECUTION EN PLUSIEURS MORCEAUX : relancer le script en entier, d''un seul bloc.';
  end if;
  b := current_setting('boygames.mig_before')::jsonb;
  if a is distinct from b then raise exception 'GARDE-FOU : des donnees existantes auraient change (% -> %). Rien n''a ete applique.', b, a; end if;
  if has_function_privilege('anon', 'public.beta_redeem(text)', 'execute')
     or has_function_privilege('anon', 'public.staff_beta_invite_create(int,int,text)', 'execute')
     or has_table_privilege('authenticated', 'public.beta_invites', 'select')
     or has_table_privilege('authenticated', 'public.beta_invite_uses', 'select') then
    raise exception 'GARDE-FOU DROITS : permissions inattendues. Rien n''a été appliqué.';
  end if;
end $$;

commit;

select 'Migration v18 appliquée (invitations bêta)' as resultat, (select count(*) from public.beta_invites) as invitations,
  (select count(*) from public.beta_members) as membres;

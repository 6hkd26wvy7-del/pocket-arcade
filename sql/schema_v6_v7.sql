-- ============================================================================
-- BOYGAMES — MIGRATION DÉFINITIVE V6 + V7  (à lancer sur boygam-test UNIQUEMENT)
-- Contenu : sauvegarde complète, contrôle d'accès des duels, fin des transferts de BC,
--           avatars, badge affiché, blocage, fiches d'amis, badges exclusifs de bêta,
--           signalement de bugs, DURCISSEMENT DES DROITS (liste blanche des fonctions, tables en lecture seule).
--
-- ATOMIQUE : tout est dans une seule transaction. Au moindre problème, RIEN n'est appliqué.
-- RÉPÉTABLE : peut être relancée sans effet secondaire.
-- GARDE-FOUS : avant de valider, le script compare les comptes (profils, scores, messages,
--   BOYCOINS, XP, amitiés, badges, objets...) avant/après. S'il y a la moindre différence,
--   il s'annule tout seul.
-- NE SUPPRIME AUCUNE DONNÉE. Précisions honnêtes :
--   * "drop function" ne vise que send_gift (cadeaux de BC, supprimés volontairement) et
--     l'ancienne my_friends (recréée avec 2 colonnes de plus). Aucune table n'est supprimée.
--   * block_user() contient un "delete" d'amitié : il ne s'exécute QUE lorsqu'un joueur en
--     bloque un autre. La migration ne l'appelle jamais.
--   * Les soldes de BOYCOINS, XP, scores, messages, récompenses ne sont jamais modifiés.
-- ============================================================================
begin;

-- Pré-contrôle : le schéma actuel doit être celui attendu (sinon on s'arrête avant toute modification)
do $$
declare t text; f text;
begin
  foreach t in array array['profiles','player_stats','scores','bc_ledger','user_badges','user_items','login_streaks',
      'friendships','messages','notifications','season_claims','mission_claims','reports','bans','user_roles',
      'beta_members','news','banned_words','app_settings','badges','shop_items'] loop
    if to_regclass('public.' || t) is null then raise exception 'PRE-CONTROLE: table manquante %', t; end if;
  end loop;
  foreach f in array array['guard_action','is_admin','is_staff','is_banned','uid_of','pseudo_of','are_friends','notify','my_role'] loop
    if not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = f) then
      raise exception 'PRE-CONTROLE: fonction manquante %', f; end if;
  end loop;
end $$;

-- Photographie avant migration, gardée dans la transaction (pas de table temporaire).
-- Garde-fou : si l'éditeur exécutait le script en plusieurs morceaux, le script s'arrête ici, avant toute modification.
do $$
begin
  perform set_config('boygames.mig_tx', txid_current()::text, true);
  perform set_config('boygames.mig_before', (jsonb_build_object(
    'profiles', (select count(*) from public.profiles), 'scores', (select count(*) from public.scores),
    'messages', (select count(*) from public.messages), 'friendships', (select count(*) from public.friendships),
    'bc_ledger', (select count(*) from public.bc_ledger), 'notifications', (select count(*) from public.notifications),
    'user_items', (select count(*) from public.user_items), 'beta_members', (select count(*) from public.beta_members),
    'user_roles', (select count(*) from public.user_roles), 'season_claims', (select count(*) from public.season_claims),
    'player_stats', (select count(*) from public.player_stats),
    'sum_bc', (select coalesce(sum(bc), 0) from public.player_stats), 'sum_xp', (select coalesce(sum(xp), 0) from public.player_stats),
    'sum_scores', (select coalesce(sum(score), 0) from public.scores),
    'badges_deja_obtenus', (select count(*) from public.user_badges where badge_code not in ('beta_founder','founder'))))::text, true);
end $$;
do $$
begin
  if coalesce(current_setting('boygames.mig_tx', true), '') <> txid_current()::text
     or coalesce(current_setting('boygames.mig_before', true), '') = '' then
    raise exception 'EXECUTION EN PLUSIEURS MORCEAUX : ce script doit etre lance en entier, d''un seul bloc. Rien n''a ete modifie.';
  end if;
end $$;

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
-- La liste inclut déjà les fonctions de la v8+v9 (BoyBlocks, paliers) : relancer ce script après la v8+v9 ne les coupe plus.
-- Toute nouvelle fonction appelée par le site doit être ajoutée aux DEUX listes « api » de ce script.
do $$
declare r record;
  api text[] := array['arena_check', 'beta_survey_get', 'beta_survey_save', 'block_user', 'boyblocks_finish', 'boyblocks_start', 'boyblocks_start_v2', 'boyblocks_start_v3', 'game_settings_public', 'my_tiers', 'public_tiers', 'set_favorites', 'sync_tiers', 'buy_item', 'claim_daily', 'claim_mission', 'claim_season_rewards', 'conversation', 'delete_my_account', 'economy_public', 'equip_item', 'get_maintenance', 'leaderboard', 'leaderboard_friends', 'leaderboard_season', 'mark_notifications_read', 'me', 'monetization_public', 'my_access', 'my_blocks', 'my_friends', 'my_missions', 'my_notifications', 'my_role', 'my_season_rewards', 'my_standing', 'public_profile', 'remove_friend', 'report_user', 'rewarded_continue', 'respond_friend_request', 'send_friend_request', 'send_message', 'set_avatar', 'set_featured_badge', 'submit_bug_report', 'submit_continued_score', 'submit_score', 'unblock_user'];
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

-- Vérification : aucune fonction hors liste blanche ne doit être exécutable par un joueur ou un visiteur.
do $$
declare r record; bad text := '';
  api text[] := array['arena_check', 'beta_survey_get', 'beta_survey_save', 'block_user', 'boyblocks_finish', 'boyblocks_start', 'boyblocks_start_v2', 'boyblocks_start_v3', 'game_settings_public', 'my_tiers', 'public_tiers', 'set_favorites', 'sync_tiers', 'buy_item', 'claim_daily', 'claim_mission', 'claim_season_rewards', 'conversation', 'delete_my_account', 'economy_public', 'equip_item', 'get_maintenance', 'leaderboard', 'leaderboard_friends', 'leaderboard_season', 'mark_notifications_read', 'me', 'monetization_public', 'my_access', 'my_blocks', 'my_friends', 'my_missions', 'my_notifications', 'my_role', 'my_season_rewards', 'my_standing', 'public_profile', 'remove_friend', 'report_user', 'rewarded_continue', 'respond_friend_request', 'send_friend_request', 'send_message', 'set_avatar', 'set_featured_badge', 'submit_bug_report', 'submit_continued_score', 'submit_score', 'unblock_user'];
begin
  for r in select p.proname, p.oid::regprocedure as sig from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' loop
    if has_function_privilege('authenticated', r.sig, 'execute') and not (r.proname = any(api) or r.proname like 'staff\_%') then bad := bad || ' ' || r.sig::text; end if;
    if has_function_privilege('anon', r.sig, 'execute') and r.proname not in ('get_maintenance','leaderboard','leaderboard_season','monetization_public','game_settings_public') then bad := bad || ' anon:' || r.sig::text; end if;
  end loop;
  if bad <> '' then raise exception 'GARDE-FOU DROITS: fonctions exposees a tort :%', bad; end if;
  if has_table_privilege('authenticated', 'public.player_stats', 'update') or has_table_privilege('authenticated', 'public.user_badges', 'insert') then
    raise exception 'GARDE-FOU DROITS: ecriture directe encore possible';
  end if;
end $$;

-- Contrôle après migration : rien ne doit avoir changé (sauf les badges exclusifs, uniquement ajoutés)
do $$
declare b jsonb; a jsonb := jsonb_build_object(
    'profiles', (select count(*) from public.profiles), 'scores', (select count(*) from public.scores),
    'messages', (select count(*) from public.messages), 'friendships', (select count(*) from public.friendships),
    'bc_ledger', (select count(*) from public.bc_ledger), 'notifications', (select count(*) from public.notifications),
    'user_items', (select count(*) from public.user_items), 'beta_members', (select count(*) from public.beta_members),
    'user_roles', (select count(*) from public.user_roles), 'season_claims', (select count(*) from public.season_claims),
    'player_stats', (select count(*) from public.player_stats),
    'sum_bc', (select coalesce(sum(bc), 0) from public.player_stats), 'sum_xp', (select coalesce(sum(xp), 0) from public.player_stats),
    'sum_scores', (select coalesce(sum(score), 0) from public.scores),
    'badges_deja_obtenus', (select count(*) from public.user_badges where badge_code not in ('beta_founder','founder')));
begin
  if coalesce(current_setting('boygames.mig_tx', true), '') <> txid_current()::text then
    raise exception 'EXECUTION EN PLUSIEURS MORCEAUX : relancer le script en entier, d''un seul bloc.';
  end if;
  b := current_setting('boygames.mig_before')::jsonb;
  if a is distinct from b then
    raise exception 'GARDE-FOU: des donnees existantes auraient change (% -> %). Migration annulee, rien n''a ete modifie.', b, a;
  end if;
end $$;

commit;

-- Résultat lisible (à regarder après "Success") :
select 'Migration appliquée' as etat,
       (select count(*) from public.profiles) as profils,
       (select count(*) from public.user_badges where badge_code = 'beta_founder') as badges_fondatrice_attribues,
       (select count(*) from public.user_badges where badge_code = 'founder') as badge_fondateur_attribue,
       (select count(*) from public.avatars) as avatars,
       (select count(*) from public.bug_reports) as signalements;

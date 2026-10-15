-- BOYGAMES — MIGRATION v12 : préparation de la monétisation (TEST uniquement, rien de réel)
-- À lancer APRÈS la v11. Tout-ou-rien, relançable. Tout est DÉSACTIVÉ par défaut.
-- A. Emplacements publicitaires configurables (jamais pendant une partie ni un duel ; pas pour les Premium).
-- B. Continuation par vidéo en solo : le score d'avant la continuation compte normalement ; le score final « continué »
--    est rangé à part (scores_continued) : ni classement, ni record, ni mission, ni palier. XP oui, BC selon réglage (0).
-- C. BOYGAMES Premium (0,99 €/mois prévu) : abonnement simulé par l'équipe (source « test »), badge Premium visible,
--    cosmétiques réservés, aucun avantage en jeu ; badge à vie « Pionnier Premium » pour les premiers abonnés.
-- Aucune transaction, aucun paiement, aucune publicité réelle.
begin;

do $$ begin
  if to_regclass('public.economy_settings') is null then
    raise exception 'PRE-CONTROLE : la migration v11 doit être lancée AVANT celle-ci. Rien n''a été modifié.';
  end if;
end $$;

do $$
begin
  perform set_config('boygames.mig_tx', txid_current()::text, true);
  perform set_config('boygames.mig_before', (jsonb_build_object(
    'profiles', (select count(*) from public.profiles), 'scores', (select count(*) from public.scores),
    'user_badges', (select count(*) from public.user_badges), 'bc_ledger', (select count(*) from public.bc_ledger),
    'user_items', (select count(*) from public.user_items),
    'sum_bc', (select coalesce(sum(bc), 0) from public.player_stats), 'sum_xp', (select coalesce(sum(xp), 0) from public.player_stats)))::text, true);
end $$;
do $$
begin
  if coalesce(current_setting('boygames.mig_tx', true), '') <> txid_current()::text
     or coalesce(current_setting('boygames.mig_before', true), '') = '' then
    raise exception 'EXECUTION EN PLUSIEURS MORCEAUX : ce script doit etre lance en entier, d''un seul bloc. Rien n''a ete modifie.';
  end if;
end $$;

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

-- ============ Contrôles ============
do $$
declare b jsonb; a jsonb := jsonb_build_object(
    'profiles', (select count(*) from public.profiles), 'scores', (select count(*) from public.scores),
    'user_badges', (select count(*) from public.user_badges), 'bc_ledger', (select count(*) from public.bc_ledger),
    'user_items', (select count(*) from public.user_items),
    'sum_bc', (select coalesce(sum(bc), 0) from public.player_stats), 'sum_xp', (select coalesce(sum(xp), 0) from public.player_stats));
begin
  if coalesce(current_setting('boygames.mig_tx', true), '') <> txid_current()::text then
    raise exception 'EXECUTION EN PLUSIEURS MORCEAUX : relancer le script en entier, d''un seul bloc.';
  end if;
  b := current_setting('boygames.mig_before')::jsonb;
  if a is distinct from b then
    raise exception 'GARDE-FOU : des donnees existantes auraient change (% -> %). Rien n''a ete applique.', b, a;
  end if;
  if has_function_privilege('authenticated', 'public.is_premium(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.monet(text)', 'execute')
     or has_function_privilege('anon', 'public.rewarded_continue(text)', 'execute')
     or has_function_privilege('anon', 'public.staff_premium_set(text,integer)', 'execute')
     or not has_function_privilege('anon', 'public.monetization_public()', 'execute')
     or has_table_privilege('authenticated', 'public.premium_subscriptions', 'insert')
     or has_table_privilege('authenticated', 'public.monetization_settings', 'select') then
    raise exception 'GARDE-FOU DROITS : permissions inattendues. Rien n''a été appliqué.';
  end if;
end $$;

commit;

select 'Migration v12 appliquée (tout désactivé, rien de réel)' as resultat,
  (select jsonb_object_agg(key, value) from public.monetization_settings) as reglages;

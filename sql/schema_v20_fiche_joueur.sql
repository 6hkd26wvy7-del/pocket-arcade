-- BOYGAMES — MIGRATION v20 : fiche administrative d'un joueur + journal des interventions (TEST)
-- À lancer APRÈS la v19. Tout-ou-rien, relançable. Ne modifie aucune donnée existante.
-- Journal : rempli AUTOMATIQUEMENT par des déclencheurs sur les tables déjà utilisées par les actions existantes
-- (bannissements, bêta, rôles, décisions de badge, signalements traités, badges exclusifs). Aucune fonction existante
-- n'est réécrite. Le journal n'est lisible que par l'équipe et ne peut être ni modifié ni effacé par le site.
-- Fiche : lecture seule ; jamais de mot de passe, d'e-mail ni de message privé.
begin;

do $$ begin
  if to_regprocedure('public.staff_players()') is null then
    raise exception 'PRE-CONTROLE : la migration v19 doit être lancée AVANT celle-ci. Rien n''a été modifié.';
  end if;
end $$;

do $$
begin
  perform set_config('boygames.mig_tx', txid_current()::text, true);
  perform set_config('boygames.mig_before', (jsonb_build_object(
    'profiles', (select count(*) from public.profiles), 'scores', (select count(*) from public.scores),
    'bans', (select count(*) from public.bans), 'beta_members', (select count(*) from public.beta_members),
    'user_badges', (select count(*) from public.user_badges), 'sum_bc', (select coalesce(sum(bc), 0) from public.player_stats)))::text, true);
end $$;
do $$
begin
  if coalesce(current_setting('boygames.mig_tx', true), '') <> txid_current()::text
     or coalesce(current_setting('boygames.mig_before', true), '') = '' then
    raise exception 'EXECUTION EN PLUSIEURS MORCEAUX : ce script doit etre lance en entier, d''un seul bloc. Rien n''a ete modifie.';
  end if;
end $$;

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

-- ============ Contrôles ============
do $$
declare b jsonb; a jsonb := jsonb_build_object(
    'profiles', (select count(*) from public.profiles), 'scores', (select count(*) from public.scores),
    'bans', (select count(*) from public.bans), 'beta_members', (select count(*) from public.beta_members),
    'user_badges', (select count(*) from public.user_badges), 'sum_bc', (select coalesce(sum(bc), 0) from public.player_stats));
begin
  if coalesce(current_setting('boygames.mig_tx', true), '') <> txid_current()::text then
    raise exception 'EXECUTION EN PLUSIEURS MORCEAUX : relancer le script en entier, d''un seul bloc.';
  end if;
  b := current_setting('boygames.mig_before')::jsonb;
  if a is distinct from b then raise exception 'GARDE-FOU : des donnees existantes auraient change (% -> %). Rien n''a ete applique.', b, a; end if;
  if has_function_privilege('anon', 'public.staff_player_detail(text)', 'execute')
     or has_function_privilege('authenticated', 'public.trg_admin_log()', 'execute')
     or has_table_privilege('authenticated', 'public.admin_actions', 'select')
     or has_table_privilege('authenticated', 'public.admin_actions', 'delete') then
    raise exception 'GARDE-FOU DROITS : permissions inattendues. Rien n''a été appliqué.';
  end if;
end $$;

commit;

select 'Migration v20 appliquée (fiche joueur, journal des interventions)' as resultat;

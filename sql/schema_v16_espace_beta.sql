-- BOYGAMES — MIGRATION v16 : espace bêta-testeur, missions, badge « BÊTA-TESTEUR BOYGAMES », suivi bêta (TEST)
-- À lancer APRÈS la v15. Tout-ou-rien, relançable. Ne touche à aucune donnée existante (aucun badge n'est attribué ici).
-- Missions : chaque testeur indique pour chaque mission « non testé / réussi / problème / impossible ». La liste des
-- missions (et la « manche ») vit dans app_settings.beta_missions : changer de version = nouvelle manche, l'ancienne reste.
-- Badge : attribué UNIQUEMENT par un administrateur, et seulement si le testeur est éligible (missions remplies +
-- questionnaire envoyé). Trouver un bug n'est pas nécessaire. Badge exclusif = permanent (déclencheur existant).
begin;

do $$ begin
  if to_regclass('public.beta_survey') is null then
    raise exception 'PRE-CONTROLE : la migration v15 doit être lancée AVANT celle-ci. Rien n''a été modifié.';
  end if;
end $$;

do $$
begin
  perform set_config('boygames.mig_tx', txid_current()::text, true);
  perform set_config('boygames.mig_before', (jsonb_build_object(
    'profiles', (select count(*) from public.profiles), 'scores', (select count(*) from public.scores),
    'bc_ledger', (select count(*) from public.bc_ledger), 'user_badges', (select count(*) from public.user_badges),
    'boyblocks_runs', (select count(*) from public.boyblocks_runs), 'beta_survey', (select count(*) from public.beta_survey),
    'sum_bc', (select coalesce(sum(bc), 0) from public.player_stats), 'sum_xp', (select coalesce(sum(xp), 0) from public.player_stats)))::text, true);
end $$;
do $$
begin
  if coalesce(current_setting('boygames.mig_tx', true), '') <> txid_current()::text
     or coalesce(current_setting('boygames.mig_before', true), '') = '' then
    raise exception 'EXECUTION EN PLUSIEURS MORCEAUX : ce script doit etre lance en entier, d''un seul bloc. Rien n''a ete modifie.';
  end if;
end $$;

-- ============ Données ============
insert into public.app_settings (key, value) values ('beta_missions', '{"version": 1,
  "codes": ["compte", "snake", "boyblocks", "space", "multi", "amis", "boybot", "classements", "progression", "mobile", "questionnaire"],
  "required": ["compte", "snake", "boyblocks", "space", "multi", "amis", "boybot", "classements", "progression", "mobile", "questionnaire"]}')
on conflict (key) do nothing;

insert into public.badges (code, name, description, sort, exclusive) values
 ('beta_tester', 'BÊTA-TESTEUR BOYGAMES', 'A réellement participé à la bêta : missions remplies, questionnaire envoyé, validé par l''équipe. Badge permanent.', 102, true)
on conflict (code) do nothing;                                            -- ne remplace jamais un badge existant

create table if not exists public.beta_missions (
  user_id uuid not null references auth.users(id) on delete cascade,
  version int not null,
  code text not null check (code ~ '^[a-z][a-z0-9_]{1,23}$'),
  status text not null check (status in ('non_teste', 'reussi', 'probleme', 'impossible')),
  note text not null default '' check (char_length(note) <= 500),
  updated_at timestamptz not null default now(),
  primary key (user_id, version, code)
);
alter table public.beta_missions enable row level security;
revoke all on public.beta_missions from anon, authenticated;

-- décisions de l'équipe sur le badge (historique : qui, quand, pourquoi)
create table if not exists public.beta_validations (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  decision text not null check (decision in ('valide', 'a_revoir')),
  note text not null default '' check (char_length(note) <= 500),
  by_user uuid references auth.users(id) on delete set null,
  at timestamptz not null default now()
);
alter table public.beta_validations enable row level security;
revoke all on public.beta_validations from anon, authenticated;

-- ============ Fonctions internes ============
create or replace function public.beta_cfg() returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce((select value from public.app_settings where key = 'beta_missions'), '{"version": 1, "codes": [], "required": []}'::jsonb);
$$;

-- Preuves déjà présentes en base (affichées à titre d'indice, jamais transformées en validation automatique).
create or replace function public.beta_evidence(p_uid uuid) returns jsonb language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'compte', exists (select 1 from public.profiles where id = p_uid),
    'snake', (select count(*) from public.scores where user_id = p_uid and game = 'snake'),
    'boyblocks', (select count(*) from public.scores where user_id = p_uid and game in ('boyblocks', 'boyblocks9')),
    'space', (select count(*) from public.scores where user_id = p_uid and game = 'space'),
    'amis', (select count(*) from public.friendships where status = 'accepted' and p_uid in (user_a, user_b)),
    'classements', (select count(*) from public.scores where user_id = p_uid),
    'progression', (select jsonb_build_object('xp', coalesce(max(xp), 0), 'niveau', coalesce(max(level), 1), 'bc', coalesce(max(bc), 0),
                      'badges', (select count(*) from public.user_badges where user_id = p_uid)) from public.player_stats where user_id = p_uid),
    'questionnaire', (select completed_at is not null from public.beta_survey where user_id = p_uid));
$$;

-- Éligible au badge : toutes les missions obligatoires remplies (réussi, problème ou impossible) + questionnaire envoyé.
create or replace function public.beta_eligible(p_uid uuid) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select completed_at is not null from public.beta_survey where user_id = p_uid), false)
     and not exists (
       select 1 from jsonb_array_elements_text(public.beta_cfg() -> 'required') req(code)
       where not exists (select 1 from public.beta_missions m where m.user_id = p_uid and m.version = (public.beta_cfg() ->> 'version')::int
                           and m.code = req.code and m.status <> 'non_teste'));
$$;

-- ============ Fonctions du site (testeur) ============
create or replace function public.beta_space() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); cfg jsonb := public.beta_cfg();
begin
  perform public.guard_action(uid);
  return jsonb_build_object('version', (cfg ->> 'version')::int, 'codes', cfg -> 'codes', 'required', cfg -> 'required',
    'missions', coalesce((select jsonb_object_agg(code, jsonb_build_object('status', status, 'note', note, 'updated_at', updated_at))
                 from public.beta_missions where user_id = uid and version = (cfg ->> 'version')::int), '{}'::jsonb),
    'evidence', public.beta_evidence(uid),
    'eligible', public.beta_eligible(uid),
    'badge', exists (select 1 from public.user_badges where user_id = uid and badge_code = 'beta_tester'),
    'bugs', (select count(*) from public.bug_reports where user_id = uid));
end $$;

create or replace function public.beta_mission_set(p_code text, p_status text, p_note text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); cfg jsonb := public.beta_cfg();
begin
  perform public.guard_action(uid);
  if p_code is null or not (cfg -> 'codes') ? p_code then raise exception 'unknown mission'; end if;
  if p_status not in ('non_teste', 'reussi', 'probleme', 'impossible') then raise exception 'invalid status'; end if;
  if char_length(coalesce(p_note, '')) > 500 then raise exception 'note too long'; end if;
  insert into public.beta_missions (user_id, version, code, status, note) values (uid, (cfg ->> 'version')::int, p_code, p_status, trim(coalesce(p_note, '')))
  on conflict (user_id, version, code) do update set status = excluded.status, note = excluded.note, updated_at = now();
  return jsonb_build_object('ok', true, 'eligible', public.beta_eligible(uid));
end $$;

-- ============ Équipe : suivi bêta ============
-- Testeurs = membres de la bêta + tous ceux qui ont rempli une mission ou le questionnaire. Aucune donnée privée (pas d'e-mail).
create or replace function public.staff_beta_overview() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare cfg jsonb := public.beta_cfg(); v int := (public.beta_cfg() ->> 'version')::int;
begin
  if not public.is_staff() then raise exception 'forbidden'; end if;
  return jsonb_build_object('version', v, 'codes', cfg -> 'codes', 'required', cfg -> 'required',
    'beta_on', coalesce((select (value ->> 'on')::boolean from public.app_settings where key = 'beta'), false),
    'testers', coalesce((select jsonb_agg(t order by t ->> 'pseudo') from (
      select jsonb_build_object('pseudo', p.pseudo, 'member', exists (select 1 from public.beta_members b where b.user_id = u.id),
        'missions', coalesce((select jsonb_object_agg(m.code, m.status) from public.beta_missions m where m.user_id = u.id and m.version = v), '{}'::jsonb),
        'notes', coalesce((select jsonb_object_agg(m.code, m.note) from public.beta_missions m where m.user_id = u.id and m.version = v and m.note <> ''), '{}'::jsonb),
        'last_update', (select max(updated_at) from public.beta_missions m where m.user_id = u.id),
        'survey', (select completed_at from public.beta_survey s where s.user_id = u.id),
        'survey_draft', exists (select 1 from public.beta_survey s where s.user_id = u.id and s.completed_at is null),
        'bugs', (select count(*) from public.bug_reports r where r.user_id = u.id),
        'evidence', public.beta_evidence(u.id), 'eligible', public.beta_eligible(u.id),
        'badge', exists (select 1 from public.user_badges ub where ub.user_id = u.id and ub.badge_code = 'beta_tester'),
        'decision', (select jsonb_build_object('decision', d.decision, 'note', d.note, 'at', d.at, 'by', public.pseudo_of(d.by_user))
                     from public.beta_validations d where d.user_id = u.id order by d.at desc limit 1)) t
      from (select user_id id from public.beta_members union select user_id from public.beta_missions union select user_id from public.beta_survey) u
      join public.profiles p on p.id = u.id) x), '[]'::jsonb));
end $$;

-- Validation finale du badge (fondateur / admin). « valide » exige l'éligibilité ; « a_revoir » note simplement la décision.
create or replace function public.staff_beta_validate(p_pseudo text, p_decision text, p_note text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare target uuid := public.uid_of(p_pseudo); added int := 0;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  if target is null then raise exception 'unknown player'; end if;
  if p_decision not in ('valide', 'a_revoir') then raise exception 'invalid decision'; end if;
  if p_decision = 'valide' then
    if not public.beta_eligible(target) then raise exception 'not eligible'; end if;
    insert into public.user_badges (user_id, badge_code) values (target, 'beta_tester') on conflict do nothing;
    get diagnostics added = row_count;
    if added > 0 then perform public.notify(target, 'badge', 'Badge BÊTA-TESTEUR BOYGAMES obtenu. Merci pour ta participation !'); end if;
  end if;
  insert into public.beta_validations (user_id, decision, note, by_user) values (target, p_decision, left(coalesce(p_note, ''), 500), auth.uid());
  return jsonb_build_object('ok', true, 'badge_added', added > 0);
end $$;

-- Nouvelle manche de missions après une mise à jour (les réponses de la manche précédente sont conservées).
create or replace function public.staff_beta_new_round() returns int language plpgsql security definer set search_path = public as $$
declare nv int;
begin
  if not public.is_admin() then raise exception 'forbidden'; end if;
  nv := (public.beta_cfg() ->> 'version')::int + 1;
  update public.app_settings set value = jsonb_set(value, '{version}', to_jsonb(nv)) where key = 'beta_missions';
  insert into public.economy_log (by_user, what, old_value, new_value) values (auth.uid(), 'beta:missions_round', to_jsonb(nv - 1), to_jsonb(nv));
  return nv;
end $$;

-- ============ Droits ============
revoke all on function public.beta_cfg(), public.beta_evidence(uuid), public.beta_eligible(uuid) from public, anon, authenticated;
revoke all on function public.beta_space(), public.beta_mission_set(text, text, text), public.staff_beta_overview(),
  public.staff_beta_validate(text, text, text), public.staff_beta_new_round() from public, anon;
grant execute on function public.beta_space(), public.beta_mission_set(text, text, text), public.staff_beta_overview(),
  public.staff_beta_validate(text, text, text), public.staff_beta_new_round() to authenticated;

-- ============ Contrôles ============
do $$
declare b jsonb; a jsonb := jsonb_build_object(
    'profiles', (select count(*) from public.profiles), 'scores', (select count(*) from public.scores),
    'bc_ledger', (select count(*) from public.bc_ledger), 'user_badges', (select count(*) from public.user_badges),
    'boyblocks_runs', (select count(*) from public.boyblocks_runs), 'beta_survey', (select count(*) from public.beta_survey),
    'sum_bc', (select coalesce(sum(bc), 0) from public.player_stats), 'sum_xp', (select coalesce(sum(xp), 0) from public.player_stats));
begin
  if coalesce(current_setting('boygames.mig_tx', true), '') <> txid_current()::text then
    raise exception 'EXECUTION EN PLUSIEURS MORCEAUX : relancer le script en entier, d''un seul bloc.';
  end if;
  b := current_setting('boygames.mig_before')::jsonb;
  if a is distinct from b then raise exception 'GARDE-FOU : des donnees existantes auraient change (% -> %). Rien n''a ete applique.', b, a; end if;
  if has_function_privilege('authenticated', 'public.beta_eligible(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.beta_evidence(uuid)', 'execute')
     or has_function_privilege('anon', 'public.beta_mission_set(text,text,text)', 'execute')
     or has_function_privilege('anon', 'public.staff_beta_validate(text,text,text)', 'execute')
     or has_table_privilege('authenticated', 'public.beta_missions', 'select')
     or has_table_privilege('authenticated', 'public.beta_validations', 'insert') then
    raise exception 'GARDE-FOU DROITS : permissions inattendues. Rien n''a été appliqué.';
  end if;
  if not (select exclusive from public.badges where code = 'beta_tester') then
    raise exception 'GARDE-FOU BADGE : le code beta_tester existe déjà avec un autre sens. Rien n''a été appliqué.';
  end if;
end $$;

commit;

select 'Migration v16 appliquée (espace bêta, missions, badge sur validation)' as resultat,
  (select value -> 'version' from public.app_settings where key = 'beta_missions') as manche,
  (select count(*) from public.user_badges where badge_code = 'beta_tester') as badges_beta_tester;

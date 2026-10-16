-- BOYGAMES — MIGRATION v15 : questionnaire des bêta-testeurs (TEST)
-- À lancer APRÈS la v14. Tout-ou-rien, relançable. Ne touche à aucune donnée existante.
-- Une ligne de réponses par testeur, modifiable à tout moment (brouillon enregistré à chaque question, puis « envoyé »).
-- Les questions elles-mêmes vivent dans le site (liste QUESTIONNAIRE) : la base ne garde que des identifiants courts.
begin;

do $$ begin
  if to_regclass('public.game_settings') is null then
    raise exception 'PRE-CONTROLE : la migration v14 doit être lancée AVANT celle-ci. Rien n''a été modifié.';
  end if;
end $$;

do $$
begin
  perform set_config('boygames.mig_tx', txid_current()::text, true);
  perform set_config('boygames.mig_before', (jsonb_build_object(
    'profiles', (select count(*) from public.profiles), 'scores', (select count(*) from public.scores),
    'bc_ledger', (select count(*) from public.bc_ledger), 'user_badges', (select count(*) from public.user_badges),
    'boyblocks_runs', (select count(*) from public.boyblocks_runs),
    'sum_bc', (select coalesce(sum(bc), 0) from public.player_stats)))::text, true);
end $$;
do $$
begin
  if coalesce(current_setting('boygames.mig_tx', true), '') <> txid_current()::text
     or coalesce(current_setting('boygames.mig_before', true), '') = '' then
    raise exception 'EXECUTION EN PLUSIEURS MORCEAUX : ce script doit etre lance en entier, d''un seul bloc. Rien n''a ete modifie.';
  end if;
end $$;

-- ============ Table ============
create table if not exists public.beta_survey (
  user_id uuid primary key references auth.users(id) on delete cascade,
  version int not null default 1,
  answers jsonb not null default '{}'::jsonb,        -- { "q_snake_speed": "parfaite", "q_tactile_pb": ["zoom", "defile"], ... }
  comment text not null default '' check (char_length(comment) <= 2000),
  completed_at timestamptz,                          -- null = brouillon (questionnaire pas encore envoyé)
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  saves int not null default 0
);
alter table public.beta_survey enable row level security;
revoke all on public.beta_survey from anon, authenticated;

-- ============ Fonctions du site ============
-- Ses propres réponses (pour reprendre ou modifier).
create or replace function public.beta_survey_get() returns jsonb language plpgsql stable security definer set search_path = public as $$
declare uid uuid := auth.uid(); r public.beta_survey;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  select * into r from public.beta_survey where user_id = uid;
  if not found then return null; end if;
  return jsonb_build_object('version', r.version, 'answers', r.answers, 'comment', r.comment,
    'completed_at', r.completed_at, 'updated_at', r.updated_at);
end $$;

-- Enregistre (ou remplace) ses réponses. p_complete = true quand le testeur appuie sur « Envoyer ».
-- Contrôles : identifiants courts (lettres, chiffres, _), choix simple ou liste de 10 choix au plus.
create or replace function public.beta_survey_save(p_answers jsonb, p_comment text default '', p_complete boolean default false, p_version int default 1)
returns jsonb language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); k text; v jsonb; x jsonb; c text := trim(coalesce(p_comment, '')); r public.beta_survey;
begin
  perform public.guard_action(uid);
  if p_answers is null or jsonb_typeof(p_answers) <> 'object' then raise exception 'invalid answers'; end if;
  if (select count(*) from jsonb_object_keys(p_answers)) > 60 then raise exception 'invalid answers'; end if;
  if p_version is null or p_version not between 1 and 99 then raise exception 'invalid version'; end if;
  if char_length(c) > 2000 then raise exception 'comment too long'; end if;
  for k, v in select * from jsonb_each(p_answers) loop
    if k !~ '^[a-z][a-z0-9_]{1,23}$' then raise exception 'invalid answers'; end if;
    if jsonb_typeof(v) = 'string' then
      if (v #>> '{}') !~ '^[a-z0-9_]{1,24}$' then raise exception 'invalid answers'; end if;
    elsif jsonb_typeof(v) = 'array' then
      if jsonb_array_length(v) > 10 then raise exception 'invalid answers'; end if;
      for x in select * from jsonb_array_elements(v) loop
        if jsonb_typeof(x) <> 'string' or (x #>> '{}') !~ '^[a-z0-9_]{1,24}$' then raise exception 'invalid answers'; end if;
      end loop;
    elsif jsonb_typeof(v) <> 'null' then raise exception 'invalid answers';
    end if;
  end loop;
  insert into public.beta_survey as s (user_id, version, answers, comment, completed_at, saves)
  values (uid, p_version, p_answers, c, case when p_complete then now() end, 1)
  on conflict (user_id) do update set version = excluded.version, answers = excluded.answers, comment = excluded.comment,
    completed_at = case when p_complete then now() else s.completed_at end, updated_at = now(), saves = s.saves + 1
  returning * into r;
  return jsonb_build_object('ok', true, 'completed_at', r.completed_at, 'updated_at', r.updated_at);
end $$;

-- ============ Administration (équipe) ============
-- Toutes les réponses, avec le pseudo du testeur. Les statistiques sont calculées par la page « Retours bêta ».
create or replace function public.staff_beta_survey() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff() then raise exception 'forbidden'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('pseudo', coalesce(public.pseudo_of(s.user_id), '?'), 'version', s.version,
      'answers', s.answers, 'comment', s.comment, 'completed_at', s.completed_at, 'updated_at', s.updated_at) order by s.updated_at desc)
    from public.beta_survey s), '[]'::jsonb);
end $$;

-- ============ Droits ============
revoke all on function public.beta_survey_get(), public.beta_survey_save(jsonb, text, boolean, int), public.staff_beta_survey() from public, anon;
grant execute on function public.beta_survey_get(), public.beta_survey_save(jsonb, text, boolean, int), public.staff_beta_survey() to authenticated;

-- ============ Contrôles ============
do $$
declare b jsonb; a jsonb := jsonb_build_object(
    'profiles', (select count(*) from public.profiles), 'scores', (select count(*) from public.scores),
    'bc_ledger', (select count(*) from public.bc_ledger), 'user_badges', (select count(*) from public.user_badges),
    'boyblocks_runs', (select count(*) from public.boyblocks_runs),
    'sum_bc', (select coalesce(sum(bc), 0) from public.player_stats));
begin
  if coalesce(current_setting('boygames.mig_tx', true), '') <> txid_current()::text then
    raise exception 'EXECUTION EN PLUSIEURS MORCEAUX : relancer le script en entier, d''un seul bloc.';
  end if;
  b := current_setting('boygames.mig_before')::jsonb;
  if a is distinct from b then raise exception 'GARDE-FOU : des donnees existantes auraient change (% -> %). Rien n''a ete applique.', b, a; end if;
  if has_function_privilege('anon', 'public.beta_survey_save(jsonb,text,boolean,int)', 'execute')
     or has_function_privilege('anon', 'public.staff_beta_survey()', 'execute')
     or has_table_privilege('authenticated', 'public.beta_survey', 'select')
     or has_table_privilege('anon', 'public.beta_survey', 'select') then
    raise exception 'GARDE-FOU DROITS : permissions inattendues. Rien n''a été appliqué.';
  end if;
end $$;

commit;

select 'Migration v15 appliquée (questionnaire bêta)' as resultat, (select count(*) from public.beta_survey) as reponses,
  (select count(*) from public.profiles) as profils;

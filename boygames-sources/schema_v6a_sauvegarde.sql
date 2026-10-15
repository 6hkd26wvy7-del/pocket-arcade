-- BOYGAMES v6a : UNIQUEMENT la sauvegarde complète (messages inclus) + contrôle d'intégrité.
-- Ne touche à aucune donnée. A lancer AVANT schema_v6.sql, puis télécharger la sauvegarde.
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
    'app_settings',  coalesce((select jsonb_agg(to_jsonb(t)) from public.app_settings t), '[]'::jsonb)
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


-- BOYGAMES — MIGRATION v19 : liste complète des joueurs pour l'équipe (TEST)
-- À lancer APRÈS la v18. Tout-ou-rien, relançable. Lecture seule : ne modifie aucune donnée.
-- Cause corrigée (16/10) : l'administration n'avait qu'un compteur de joueurs ; un compte sans partie (ex. EL-MATHISSO)
-- n'apparaissait nulle part. Aucune adresse e-mail n'est renvoyée.
begin;

do $$ begin
  if to_regclass('public.beta_invites') is null then
    raise exception 'PRE-CONTROLE : la migration v18 doit être lancée AVANT celle-ci. Rien n''a été modifié.';
  end if;
end $$;

create or replace function public.staff_players() returns jsonb language plpgsql stable security definer set search_path = public as $$
begin
  if not public.is_staff() then raise exception 'forbidden'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'pseudo', p.pseudo, 'country', p.country, 'created_at', p.created_at,
      'last_sign_in', u.last_sign_in_at, 'confirmed', u.email_confirmed_at is not null,
      'level', coalesce(s.level, 1), 'xp', coalesce(s.xp, 0), 'bc', coalesce(s.bc, 0),
      'games', (select count(*) from public.scores sc where sc.user_id = p.id),
      'last_game', (select max(created_at) from public.scores sc where sc.user_id = p.id),
      'beta', exists (select 1 from public.beta_members b where b.user_id = p.id),
      'role', (select r.role from public.user_roles r where r.user_id = p.id),
      'banned', exists (select 1 from public.bans x where x.user_id = p.id and (x.until is null or x.until > now())),
      'badges', (select coalesce(jsonb_agg(ub.badge_code order by ub.badge_code), '[]'::jsonb) from public.user_badges ub where ub.user_id = p.id))
    order by p.created_at desc)
    from public.profiles p join auth.users u on u.id = p.id left join public.player_stats s on s.user_id = p.id), '[]'::jsonb);
end $$;
revoke all on function public.staff_players() from public, anon;
grant execute on function public.staff_players() to authenticated;

do $$ begin
  if has_function_privilege('anon', 'public.staff_players()', 'execute') then
    raise exception 'GARDE-FOU DROITS : permissions inattendues. Rien n''a été appliqué.';
  end if;
end $$;

commit;

select 'Migration v19 appliquée (liste des joueurs pour l''équipe)' as resultat;

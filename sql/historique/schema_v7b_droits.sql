-- BOYGAMES — DURCISSEMENT DES DROITS (liste blanche). Idempotent.
-- Problème corrigé : sur Supabase, les nouvelles fonctions sont par défaut exécutables par tout joueur
-- connecté (et même par les visiteurs). "revoke ... from public" ne retire PAS ces droits. Des fonctions
-- internes (add_bc, add_xp, check_badges...) pouvaient donc être appelées directement.
-- Désormais : AUCUNE fonction n'est appelable, sauf la liste blanche ci-dessous.
do $$
declare r record;
  api text[] := array['arena_check', 'block_user', 'buy_item', 'claim_daily', 'claim_mission', 'claim_season_rewards', 'conversation', 'delete_my_account', 'equip_item', 'get_maintenance', 'leaderboard', 'leaderboard_friends', 'leaderboard_season', 'mark_notifications_read', 'me', 'my_access', 'my_blocks', 'my_friends', 'my_missions', 'my_notifications', 'my_role', 'my_season_rewards', 'my_standing', 'public_profile', 'remove_friend', 'report_user', 'respond_friend_request', 'send_friend_request', 'send_message', 'set_avatar', 'set_featured_badge', 'submit_bug_report', 'submit_score', 'unblock_user'];
  anon_ok text[] := array['get_maintenance','leaderboard','leaderboard_season'];
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


-- Vérification : aucune fonction hors liste blanche ne doit être exécutable par un joueur ou un visiteur.
do $$
declare r record; bad text := '';
  api text[] := array['arena_check', 'block_user', 'buy_item', 'claim_daily', 'claim_mission', 'claim_season_rewards', 'conversation', 'delete_my_account', 'equip_item', 'get_maintenance', 'leaderboard', 'leaderboard_friends', 'leaderboard_season', 'mark_notifications_read', 'me', 'my_access', 'my_blocks', 'my_friends', 'my_missions', 'my_notifications', 'my_role', 'my_season_rewards', 'my_standing', 'public_profile', 'remove_friend', 'report_user', 'respond_friend_request', 'send_friend_request', 'send_message', 'set_avatar', 'set_featured_badge', 'submit_bug_report', 'submit_score', 'unblock_user'];
begin
  for r in select p.proname, p.oid::regprocedure as sig from pg_proc p
            where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' loop
    if has_function_privilege('authenticated', r.sig, 'execute') and not (r.proname = any(api) or r.proname like 'staff\_%') then bad := bad || ' ' || r.sig::text; end if;
    if has_function_privilege('anon', r.sig, 'execute') and r.proname not in ('get_maintenance','leaderboard','leaderboard_season') then bad := bad || ' anon:' || r.sig::text; end if;
  end loop;
  if bad <> '' then raise exception 'GARDE-FOU DROITS: fonctions exposees a tort :%', bad; end if;
  if has_table_privilege('authenticated', 'public.player_stats', 'update') or has_table_privilege('authenticated', 'public.user_badges', 'insert') then
    raise exception 'GARDE-FOU DROITS: ecriture directe encore possible';
  end if;
end $$;

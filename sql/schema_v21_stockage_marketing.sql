-- BOYGAMES — MIGRATION v21 : aperçus vidéo de l'onglet Marketing (TEST)
-- À lancer APRÈS la v20. Relançable. Ne touche à aucune donnée.
-- Cause : la règle d'accès au stockage « marketing » appelait public.is_admin(), que la liste blanche des fonctions
-- (v6/v7) interdit aux joueurs connectés -> la règle échouait toujours (erreurs 400 sur les liens signés).
-- Correction : la règle lit directement le rôle dans user_roles (lecture de sa propre ligne seulement, règle existante).
begin;

do $$ begin
  if to_regclass('public.admin_actions') is null then
    raise exception 'PRE-CONTROLE : la migration v20 doit être lancée AVANT celle-ci. Rien n''a été modifié.';
  end if;
  if to_regclass('storage.objects') is not null then
    execute 'drop policy if exists "marketing : lecture equipe" on storage.objects';
    execute 'create policy "marketing : lecture equipe" on storage.objects for select to authenticated using (bucket_id = ''marketing'' and exists (select 1 from public.user_roles r where r.user_id = auth.uid() and r.role in (''founder'', ''admin'')))';
  end if;
end $$;

commit;

select 'Migration v21 appliquée (aperçus marketing)' as resultat;

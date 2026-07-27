-- =============================================================================
-- Phase 7 (correctif utilisateur) — Désactivation de la vérification IA.
--
-- La modération automatique est retirée : un clip naît directement en
-- `published` et les candidatures artiste sont approuvées sans analyse.
-- =============================================================================

-- Réécriture du verrou : seul le blocage de l'UPDATE est conservé (le client ne
-- peut toujours pas modifier le statut d'un clip existant). À l'INSERT,
-- `published` redevient le statut autorisé.
create or replace function public.videos_guard_client_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Rôles d'administration et service_role : exemptés.
  if current_user in ('service_role', 'postgres', 'supabase_admin') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    new.view_count := 0;
    new.like_count := 0;
    new.comment_count := 0;

    -- Phase 7 : `published` est réautorisé à la création. La vérification IA
    -- est retirée.
    if new.status is distinct from 'published' then
      raise exception
        'Un clip est créé avec le statut publié, pas en statut %.',
        new.status
        using errcode = '42501';
    end if;

    -- `published_at` est posé par le trigger existant sur `status = published`.
    return new;
  end if;

  -- UPDATE côté client : les compteurs sont restaurés.
  new.view_count := old.view_count;
  new.like_count := old.like_count;
  new.comment_count := old.comment_count;

  -- Le statut reste verrouillé à l'UPDATE : seul service_role décide.
  if new.status is distinct from old.status then
    raise exception
      'Le statut d''un clip est décidé par la modération, pas par son auteur.'
      using errcode = '42501';
  end if;

  new.moderation_result := old.moderation_result;
  new.published_at := old.published_at;

  return new;
end;
$$;

comment on function public.videos_guard_client_fields() is
  'Fige les compteurs et verrouille le statut à l''UPDATE. Phase 7 : '
  'published est réautorisé à l''INSERT (la vérification IA est retirée).';

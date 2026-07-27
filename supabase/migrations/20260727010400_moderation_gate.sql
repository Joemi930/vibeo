-- =============================================================================
-- Phase 4 -- Verrou de modération vidéo.
--
-- C'est la migration la plus risquée du projet : elle retire au client la
-- possibilité de publier un clip directement. Mal faite, plus personne ne peut
-- publier. Elle est donc isolée dans son propre fichier, avec ses tests.
--
-- ── Le problème
--
-- Jusqu'ici, l'application insérait ses clips en `published` et ils étaient
-- visibles immédiatement. La modération de Phase 4 vit dans une Edge Function
-- que le client doit appeler après l'insertion. L'objection est évidente :
-- **le client peut ne pas appeler**. Un `curl` d'une ligne suffirait alors à
-- publier sans passer par la modération, et tout l'édifice ne serait qu'une
-- convention.
--
-- ── La solution
--
-- On ne compte pas sur la discipline du client : on lui retire le pouvoir.
-- `published` disparaît des statuts autorisés à la création. Le client ne peut
-- plus créer qu'un clip en `processing`, invisible de tous. Il appelle ensuite
-- `moderate-video`, qui opère en `service_role` — rôle que ce trigger exempte
-- dès sa première ligne — et qui seule peut poser `pending_moderation`, puis
-- `published` ou `rejected`.
--
-- Contourner l'appel ne permet donc rien : cela ne fait que laisser son propre
-- clip invisible. C'est la seule forme de contrainte qui tienne.
--
-- ── Ce qui reste vrai et ne doit pas changer
--
-- `current_user` est utilisé ici, et c'est correct : cette fonction n'est PAS
-- `security definer`, donc `current_user` désigne bien l'appelant réel. Le
-- piège documenté (`current_user` vaut le propriétaire dans une fonction
-- DEFINER) ne s'applique pas. Ne pas « corriger » ceci en `auth.role()` sans
-- comprendre la différence : ici, `postgres` et `supabase_admin` doivent aussi
-- être exemptés pour que les migrations et les semences fonctionnent.
--
-- ── Filets de reprise
--
-- Un clip ne doit jamais rester coincé en `processing`. Trois filets, tous
-- côté applicatif : bouton « Relancer la vérification » après l'envoi et dans
-- le Studio, et une reprise planifiée toutes les 15 minutes qui, au-delà de
-- 24 h, force `pending_moderation` — c'est-à-dire pousse le clip dans la file
-- d'attente admin. **On échoue vers l'humain, jamais vers la publication
-- automatique ni vers les limbes.**
-- =============================================================================

create or replace function public.videos_guard_client_fields()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  -- Rôles d'administration et service_role : exemptés. C'est par ce chemin que
  -- `moderate-video` pose les statuts de modération.
  if current_user in ('service_role', 'postgres', 'supabase_admin') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    -- Les compteurs démarrent toujours à zéro, jamais fournis par le client.
    new.view_count := 0;
    new.like_count := 0;
    new.comment_count := 0;

    -- CHANGEMENT DE PHASE 4 : `published` n'est plus autorisé à la création.
    -- Tout clip naît invisible et ne devient public que par la modération.
    if new.status is distinct from 'processing' then
      raise exception
        'Un clip est créé en attente de vérification, pas en statut %.',
        new.status
        using errcode = '42501';
    end if;

    -- Un clip en `processing` n'est pas publié : pas d'horodatage de
    -- publication. Il sera posé par `moderate-video` au moment réel de la
    -- publication.
    new.published_at := null;

    return new;
  end if;

  -- UPDATE côté client : les compteurs sont restaurés à leur valeur
  -- précédente, quoi que le client ait envoyé (défense en profondeur).
  new.view_count := old.view_count;
  new.like_count := old.like_count;
  new.comment_count := old.comment_count;

  -- Le client ne décide d'aucun statut, dans aucun sens.
  --
  -- La règle est désormais plus stricte qu'en Phase 3 : auparavant seules les
  -- transitions VERS un statut de modération étaient bloquées, ce qui laissait
  -- un artiste repasser lui-même un clip `rejected` en `published`. Le rejet
  -- aurait été annulable d'un clic par la personne sanctionnée.
  if new.status is distinct from old.status then
    raise exception
      'Le statut d''un clip est décidé par la modération, pas par son auteur.'
      using errcode = '42501';
  end if;

  -- Le résultat de modération n'appartient pas non plus au client : il porte
  -- le motif affiché à l'artiste, qui pourrait sinon se le réécrire.
  new.moderation_result := old.moderation_result;
  new.published_at := old.published_at;

  return new;
end;
$$;

comment on function public.videos_guard_client_fields() is
  'Fige les compteurs et retire au client toute maîtrise du statut : un clip '
  'naît en processing (invisible) et n''en sort que par moderate-video, en '
  'service_role. Sans cela, la modération serait contournable par un simple '
  'appel direct à l''API.';

-- Le trigger existe déjà (20260725010100_videos.sql) et pointe sur cette
-- fonction : `create or replace` suffit, rien à recréer.

-- -----------------------------------------------------------------------------
-- Politique RLS : le client peut toujours modifier SES clips (titre,
-- description, miniature, genre) -- seul le statut lui échappe désormais, par
-- le trigger ci-dessus. `videos_update_own` reste donc inchangée : la
-- restreindre par colonne casserait la modification légitime depuis le Studio.
-- -----------------------------------------------------------------------------

-- Index de reprise : la tâche planifiée cherche les clips en souffrance. Sans
-- index, elle balaie toute la table à chaque passage (toutes les 15 minutes).
create index if not exists videos_moderation_queue_idx
  on public.videos (status, created_at)
  where status in ('processing', 'pending_moderation');

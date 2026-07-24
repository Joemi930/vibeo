-- Seed : genres musicaux de référence.
-- Chargé automatiquement par `supabase db reset` (config db.seed).

insert into public.genres (name, slug) values
  ('Pop', 'pop'),
  ('Rock', 'rock'),
  ('Hip-Hop', 'hip-hop'),
  ('R&B', 'rnb'),
  ('Afrobeats', 'afrobeats'),
  ('Électro', 'electro'),
  ('Jazz', 'jazz'),
  ('Classique', 'classique'),
  ('Reggae', 'reggae'),
  ('Metal', 'metal'),
  ('Country', 'country'),
  ('Autre', 'autre')
on conflict (slug) do nothing;

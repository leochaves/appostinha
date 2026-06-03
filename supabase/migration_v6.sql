-- ============================================================
-- Migration v6: Código de votação por torneio
-- ============================================================

ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS voting_code TEXT;

-- ============================================================
-- Migration v9: Tipo de torneio (palpite vs moeda)
-- ============================================================

-- Colunas novas em tournaments
ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS mode         TEXT NOT NULL DEFAULT 'prediction'
    CHECK (mode IN ('prediction', 'coin')),
  ADD COLUMN IF NOT EXISTS coin_name    TEXT NOT NULL DEFAULT 'Ficha',
  ADD COLUMN IF NOT EXISTS initial_coins INTEGER NOT NULL DEFAULT 500;

-- Colunas novas em tournament_members (saldo, apenas relevante no modo moeda)
ALTER TABLE public.tournament_members
  ADD COLUMN IF NOT EXISTS coins         INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS initial_coins INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS bonus_coins   INTEGER NOT NULL DEFAULT 0;

-- ============================================================
-- Tabela de transações manuais (crédito/débito pelo admin)
-- ============================================================
CREATE TABLE IF NOT EXISTS public.transactions (
  id            UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  tournament_id UUID REFERENCES public.tournaments(id) ON DELETE CASCADE NOT NULL,
  user_id       UUID REFERENCES public.profiles(id)    ON DELETE CASCADE NOT NULL,
  amount        INTEGER NOT NULL,   -- positivo = crédito, negativo = débito
  reason        TEXT,
  affects_ranking BOOLEAN NOT NULL DEFAULT false,
  created_by    UUID REFERENCES public.profiles(id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Transações visíveis por membros"
  ON public.transactions FOR SELECT USING (true);

CREATE POLICY "Admin registra transação"
  ON public.transactions FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.tournament_admins
      WHERE tournament_id = transactions.tournament_id
        AND user_id = auth.uid()
    )
  );

-- ============================================================
-- Função: approve_member (atualizada — distribui moedas no modo coin)
-- ============================================================
CREATE OR REPLACE FUNCTION public.approve_member(
  p_tournament_id UUID,
  p_user_id       UUID
) RETURNS VOID AS $$
DECLARE
  v_mode          TEXT;
  v_initial_coins INTEGER;
BEGIN
  IF NOT public.is_tournament_admin(p_tournament_id) THEN
    RAISE EXCEPTION 'Apenas admins podem aprovar membros';
  END IF;

  SELECT mode, initial_coins
  INTO v_mode, v_initial_coins
  FROM public.tournaments
  WHERE id = p_tournament_id;

  IF v_mode = 'coin' THEN
    UPDATE public.tournament_members
    SET status = 'approved',
        approved_at = NOW(),
        approved_by = auth.uid(),
        coins = v_initial_coins,
        initial_coins = v_initial_coins
    WHERE tournament_id = p_tournament_id AND user_id = p_user_id;
  ELSE
    UPDATE public.tournament_members
    SET status = 'approved',
        approved_at = NOW(),
        approved_by = auth.uid()
    WHERE tournament_id = p_tournament_id AND user_id = p_user_id;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- Função: add_coins (admin credita/debita moedas manualmente)
-- ============================================================
CREATE OR REPLACE FUNCTION public.add_coins(
  p_tournament_id  UUID,
  p_user_id        UUID,
  p_amount         INTEGER,
  p_reason         TEXT DEFAULT NULL,
  p_affects_ranking BOOLEAN DEFAULT false
) RETURNS VOID AS $$
BEGIN
  IF NOT public.is_tournament_admin(p_tournament_id) THEN
    RAISE EXCEPTION 'Apenas admins podem adicionar moedas';
  END IF;

  -- Atualiza saldo do membro
  UPDATE public.tournament_members
  SET coins = coins + p_amount,
      bonus_coins = CASE
        WHEN NOT p_affects_ranking THEN bonus_coins + p_amount
        ELSE bonus_coins
      END
  WHERE tournament_id = p_tournament_id AND user_id = p_user_id;

  -- Registra transação
  INSERT INTO public.transactions
    (tournament_id, user_id, amount, reason, affects_ranking, created_by)
  VALUES
    (p_tournament_id, p_user_id, p_amount, p_reason, p_affects_ranking, auth.uid());
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

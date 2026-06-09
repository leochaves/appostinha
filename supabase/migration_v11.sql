-- ============================================================
-- Migration v11: Apostas em modo moeda (múltiplas por evento)
-- ============================================================

-- Remove UNIQUE (user_id, event_id) — agora controlado via RPC por modo
ALTER TABLE public.bets DROP CONSTRAINT IF EXISTS bets_user_id_event_id_key;

-- Coluna de valor apostado (só modo moeda, nullable)
ALTER TABLE public.bets
  ADD COLUMN IF NOT EXISTS amount INTEGER;

-- Pool de moedas por opção (separado de prediction_count)
ALTER TABLE public.options
  ADD COLUMN IF NOT EXISTS coin_pool INTEGER NOT NULL DEFAULT 0;

-- ============================================================
-- Função: place_coin_bet
-- Deduz fichas do membro, registra aposta, atualiza coin_pool
-- Permite múltiplas apostas no mesmo evento (inclusive mesma opção)
-- ============================================================
CREATE OR REPLACE FUNCTION public.place_coin_bet(
  p_tournament_id UUID,
  p_event_id      UUID,
  p_option_id     UUID,
  p_amount        INTEGER
) RETURNS VOID AS $$
DECLARE
  v_mode    TEXT;
  v_coins   INTEGER;
  v_status  TEXT;
BEGIN
  -- valida modo
  SELECT mode INTO v_mode FROM public.tournaments WHERE id = p_tournament_id;
  IF v_mode != 'coin' THEN
    RAISE EXCEPTION 'Este torneio não usa moedas';
  END IF;

  -- valida evento aberto
  SELECT status INTO v_status FROM public.events WHERE id = p_event_id;
  IF v_status != 'open' THEN
    RAISE EXCEPTION 'Evento não está aberto para apostas';
  END IF;

  -- valida opção
  IF NOT EXISTS (
    SELECT 1 FROM public.options WHERE id = p_option_id AND event_id = p_event_id
  ) THEN
    RAISE EXCEPTION 'Opção inválida para este evento';
  END IF;

  -- valida valor
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'O valor deve ser maior que zero';
  END IF;

  -- verifica saldo do membro
  SELECT coins INTO v_coins
  FROM public.tournament_members
  WHERE tournament_id = p_tournament_id AND user_id = auth.uid() AND status = 'approved';

  IF v_coins IS NULL THEN
    RAISE EXCEPTION 'Você não é membro aprovado deste torneio';
  END IF;

  IF v_coins < p_amount THEN
    RAISE EXCEPTION 'Saldo insuficiente (você tem % fichas)', v_coins;
  END IF;

  -- deduz saldo
  UPDATE public.tournament_members
  SET coins = coins - p_amount
  WHERE tournament_id = p_tournament_id AND user_id = auth.uid();

  -- atualiza coin_pool da opção
  UPDATE public.options
  SET coin_pool = coin_pool + p_amount
  WHERE id = p_option_id;

  -- registra aposta
  INSERT INTO public.bets (user_id, event_id, option_id, amount)
  VALUES (auth.uid(), p_event_id, p_option_id, p_amount);

  -- badge primeira previsão
  INSERT INTO public.user_badges (user_id, badge_id)
  VALUES (auth.uid(), 'first_prediction')
  ON CONFLICT (user_id, badge_id) DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- resolve_event atualizado: modo moeda paga payout parimutual
-- ============================================================
CREATE OR REPLACE FUNCTION public.resolve_event(
  p_event_id          UUID,
  p_winning_option_id UUID
) RETURNS VOID AS $$
DECLARE
  v_bet           RECORD;
  v_hit_count     INTEGER;
  v_tournament_id UUID;
  v_points        INTEGER;
  v_mode          TEXT;
  v_total_pool    INTEGER;
  v_winning_pool  INTEGER;
  v_payout        INTEGER;
BEGIN
  SELECT c.tournament_id INTO v_tournament_id
  FROM public.events e
  LEFT JOIN public.categories c ON c.id = e.category_id
  WHERE e.id = p_event_id;

  IF v_tournament_id IS NOT NULL THEN
    IF NOT public.is_tournament_admin(v_tournament_id) THEN
      RAISE EXCEPTION 'Apenas admins podem resolver eventos';
    END IF;
    SELECT mode INTO v_mode FROM public.tournaments WHERE id = v_tournament_id;
  ELSE
    IF (SELECT created_by FROM public.events WHERE id = p_event_id) != auth.uid() THEN
      RAISE EXCEPTION 'Sem permissão';
    END IF;
    v_mode := 'prediction';
  END IF;

  IF (SELECT status FROM public.events WHERE id = p_event_id) = 'resolved' THEN
    RAISE EXCEPTION 'Evento já foi resolvido';
  END IF;

  SELECT COALESCE(points, 1) INTO v_points FROM public.events WHERE id = p_event_id;

  UPDATE public.events
  SET status = 'resolved', winning_option_id = p_winning_option_id
  WHERE id = p_event_id;

  -- ── modo moeda: payout parimutual ──────────────────────────
  IF v_mode = 'coin' THEN
    SELECT COALESCE(SUM(coin_pool), 0) INTO v_total_pool
    FROM public.options WHERE event_id = p_event_id;

    SELECT COALESCE(coin_pool, 0) INTO v_winning_pool
    FROM public.options WHERE id = p_winning_option_id;

    FOR v_bet IN
      SELECT * FROM public.bets
      WHERE event_id = p_event_id AND option_id = p_winning_option_id
    LOOP
      IF v_winning_pool > 0 THEN
        v_payout := FLOOR(v_bet.amount::FLOAT / v_winning_pool::FLOAT * v_total_pool::FLOAT);
      ELSE
        v_payout := 0;
      END IF;

      UPDATE public.bets SET status = 'won', points_earned = v_payout WHERE id = v_bet.id;

      -- credita payout ao membro
      UPDATE public.tournament_members
      SET coins = coins + v_payout
      WHERE tournament_id = v_tournament_id AND user_id = v_bet.user_id;
    END LOOP;

    -- marca apostas perdedoras
    UPDATE public.bets SET status = 'lost', points_earned = 0
    WHERE event_id = p_event_id AND option_id != p_winning_option_id AND status = 'pending';

  -- ── modo palpite: pontos por peso do evento ────────────────
  ELSE
    FOR v_bet IN SELECT * FROM public.bets WHERE event_id = p_event_id
    LOOP
      IF v_bet.option_id = p_winning_option_id THEN
        UPDATE public.bets SET status = 'won', points_earned = v_points WHERE id = v_bet.id;

        SELECT COUNT(*) INTO v_hit_count
        FROM public.bets WHERE user_id = v_bet.user_id AND status = 'won';

        INSERT INTO public.user_badges (user_id, badge_id) VALUES (v_bet.user_id, 'first_hit')
        ON CONFLICT (user_id, badge_id) DO NOTHING;

        IF v_hit_count >= 5 THEN
          INSERT INTO public.user_badges (user_id, badge_id) VALUES (v_bet.user_id, '5_hits')
          ON CONFLICT (user_id, badge_id) DO NOTHING;
        END IF;
        IF v_hit_count >= 10 THEN
          INSERT INTO public.user_badges (user_id, badge_id) VALUES (v_bet.user_id, '10_hits')
          ON CONFLICT (user_id, badge_id) DO NOTHING;
        END IF;
        IF v_hit_count >= 25 THEN
          INSERT INTO public.user_badges (user_id, badge_id) VALUES (v_bet.user_id, '25_hits')
          ON CONFLICT (user_id, badge_id) DO NOTHING;
        END IF;
      ELSE
        UPDATE public.bets SET status = 'lost', points_earned = 0 WHERE id = v_bet.id;
      END IF;
    END LOOP;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- Migration v10: Peso por evento (opção B) — modo palpite
-- ============================================================

-- Coluna de peso no evento (default 1 = sem multiplicador)
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS points INTEGER NOT NULL DEFAULT 1
    CHECK (points >= 1 AND points <= 10);

-- Coluna de pontos ganhos em cada bet (preenchida ao resolver)
ALTER TABLE public.bets
  ADD COLUMN IF NOT EXISTS points_earned FLOAT NOT NULL DEFAULT 0;

-- ============================================================
-- resolve_event atualizado: salva points_earned em cada bet vencedora
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
BEGIN
  SELECT c.tournament_id INTO v_tournament_id
  FROM public.events e
  LEFT JOIN public.categories c ON c.id = e.category_id
  WHERE e.id = p_event_id;

  IF v_tournament_id IS NOT NULL THEN
    IF NOT public.is_tournament_admin(v_tournament_id) THEN
      RAISE EXCEPTION 'Apenas admins podem resolver eventos';
    END IF;
  ELSE
    IF (SELECT created_by FROM public.events WHERE id = p_event_id) != auth.uid() THEN
      RAISE EXCEPTION 'Sem permissão';
    END IF;
  END IF;

  IF (SELECT status FROM public.events WHERE id = p_event_id) != 'open' THEN
    RAISE EXCEPTION 'Evento já foi resolvido';
  END IF;

  -- peso do evento
  SELECT COALESCE(points, 1) INTO v_points
  FROM public.events WHERE id = p_event_id;

  UPDATE public.events
  SET status = 'resolved', winning_option_id = p_winning_option_id
  WHERE id = p_event_id;

  FOR v_bet IN SELECT * FROM public.bets WHERE event_id = p_event_id
  LOOP
    IF v_bet.option_id = p_winning_option_id THEN
      UPDATE public.bets
      SET status = 'won', points_earned = v_points
      WHERE id = v_bet.id;

      SELECT COUNT(*) INTO v_hit_count
      FROM public.bets WHERE user_id = v_bet.user_id AND status = 'won';

      INSERT INTO public.user_badges (user_id, badge_id)
      VALUES (v_bet.user_id, 'first_hit')
      ON CONFLICT (user_id, badge_id) DO NOTHING;

      IF v_hit_count >= 5 THEN
        INSERT INTO public.user_badges (user_id, badge_id)
        VALUES (v_bet.user_id, '5_hits')
        ON CONFLICT (user_id, badge_id) DO NOTHING;
      END IF;
      IF v_hit_count >= 10 THEN
        INSERT INTO public.user_badges (user_id, badge_id)
        VALUES (v_bet.user_id, '10_hits')
        ON CONFLICT (user_id, badge_id) DO NOTHING;
      END IF;
      IF v_hit_count >= 25 THEN
        INSERT INTO public.user_badges (user_id, badge_id)
        VALUES (v_bet.user_id, '25_hits')
        ON CONFLICT (user_id, badge_id) DO NOTHING;
      END IF;
    ELSE
      UPDATE public.bets SET status = 'lost', points_earned = 0 WHERE id = v_bet.id;
    END IF;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

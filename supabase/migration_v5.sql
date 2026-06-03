-- ============================================================
-- Migration v5: Badges de liderança por torneio
-- ============================================================

INSERT INTO public.badges (id, name, description, icon) VALUES
  ('champion_1st', 'Campeão',        'Terminou em 1º lugar num torneio', '🥇'),
  ('champion_2nd', 'Vice-Campeão',   'Terminou em 2º lugar num torneio', '🥈'),
  ('champion_3rd', 'Terceiro Lugar', 'Terminou em 3º lugar num torneio', '🥉')
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- Função: award_tournament_champions
-- Calcula o leaderboard do torneio e premia o top 3
-- Só o owner do torneio pode chamar
-- ============================================================
CREATE OR REPLACE FUNCTION public.award_tournament_champions(
  p_tournament_id UUID
) RETURNS JSONB AS $$
DECLARE
  v_row    RECORD;
  v_rank   INTEGER := 0;
  v_badge  TEXT;
  v_result JSONB := '[]'::JSONB;
BEGIN
  -- verifica se quem chama é admin do torneio
  IF NOT public.is_tournament_admin(p_tournament_id) THEN
    RAISE EXCEPTION 'Apenas admins podem premiar campeões';
  END IF;

  -- leaderboard: wins decrescente, accuracy desempate
  FOR v_row IN
    SELECT
      b.user_id,
      p.username,
      COUNT(*) FILTER (WHERE b.status = 'won') AS wins,
      COUNT(*) FILTER (WHERE b.status != 'pending') AS total
    FROM public.bets b
    JOIN public.events e  ON e.id = b.event_id
    JOIN public.categories c ON c.id = e.category_id
    JOIN public.profiles p ON p.id = b.user_id
    WHERE c.tournament_id = p_tournament_id
      AND b.status != 'pending'
    GROUP BY b.user_id, p.username
    HAVING COUNT(*) FILTER (WHERE b.status = 'won') > 0
    ORDER BY wins DESC,
             (COUNT(*) FILTER (WHERE b.status = 'won')::FLOAT /
              NULLIF(COUNT(*) FILTER (WHERE b.status != 'pending'), 0)) DESC
    LIMIT 3
  LOOP
    v_rank := v_rank + 1;

    v_badge := CASE v_rank
      WHEN 1 THEN 'champion_1st'
      WHEN 2 THEN 'champion_2nd'
      WHEN 3 THEN 'champion_3rd'
    END;

    INSERT INTO public.user_badges (user_id, badge_id, context, earned_at)
    VALUES (v_row.user_id, v_badge, p_tournament_id::TEXT, NOW())
    ON CONFLICT (user_id, badge_id) DO UPDATE
      SET context   = EXCLUDED.context,
          earned_at = EXCLUDED.earned_at;

    v_result := v_result || jsonb_build_object(
      'rank',     v_rank,
      'user_id',  v_row.user_id,
      'username', v_row.username,
      'wins',     v_row.wins,
      'badge',    v_badge
    );
  END LOOP;

  RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- Migration v2: Hierarquia Torneios/Categorias + Badges
-- Cole no SQL Editor do Supabase e execute
-- ============================================================

-- Remove funções antigas
DROP FUNCTION IF EXISTS public.place_bet(UUID, UUID, UUID, INTEGER);
DROP FUNCTION IF EXISTS public.resolve_event(UUID, UUID);

-- Remove colunas de dinheiro
ALTER TABLE public.profiles DROP COLUMN IF EXISTS balance;
ALTER TABLE public.bets     DROP COLUMN IF EXISTS amount;
ALTER TABLE public.bets     DROP COLUMN IF EXISTS payout;

-- Renomeia total_pool → prediction_count nas opções
ALTER TABLE public.options RENAME COLUMN total_pool TO prediction_count;

-- ============================================================
-- Torneios (agrupador raiz)
-- ============================================================
CREATE TABLE public.tournaments (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name        TEXT NOT NULL,
  description TEXT,
  created_by  UUID REFERENCES public.profiles(id) NOT NULL,
  status      TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'finished')),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- Categorias (dentro de um torneio)
-- ============================================================
CREATE TABLE public.categories (
  id            UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  tournament_id UUID REFERENCES public.tournaments(id) ON DELETE CASCADE NOT NULL,
  name          TEXT NOT NULL,
  created_by    UUID REFERENCES public.profiles(id) NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Associa eventos a categorias
ALTER TABLE public.events
  ADD COLUMN IF NOT EXISTS category_id UUID REFERENCES public.categories(id);

-- ============================================================
-- Badges
-- ============================================================
CREATE TABLE public.badges (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  description TEXT NOT NULL,
  icon        TEXT NOT NULL
);

CREATE TABLE public.user_badges (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id    UUID REFERENCES public.profiles(id) ON DELETE CASCADE NOT NULL,
  badge_id   TEXT REFERENCES public.badges(id) NOT NULL,
  context    TEXT,
  earned_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, badge_id)
);

INSERT INTO public.badges (id, name, description, icon) VALUES
  ('first_prediction', 'Palpiteiro', 'Fez a primeira previsão',    '🎯'),
  ('first_hit',        'Sortudo',    'Acertou pela primeira vez',   '🍀'),
  ('5_hits',           'Analista',   'Acertou 5 previsões',         '🔍'),
  ('10_hits',          'Expert',     'Acertou 10 previsões',        '⭐'),
  ('25_hits',          'Oráculo',    'Acertou 25 previsões',        '🔮'),
  ('perfect_event',    'Perfeito',   'Acertou 100% numa categoria', '🏆')
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- RLS novas tabelas
-- ============================================================
ALTER TABLE public.tournaments  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.badges       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_badges  ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Torneios visíveis"        ON public.tournaments FOR SELECT USING (true);
CREATE POLICY "Autenticado cria torneio" ON public.tournaments FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "Criador atualiza torneio" ON public.tournaments FOR UPDATE USING (auth.uid() = created_by);

CREATE POLICY "Categorias visíveis"        ON public.categories FOR SELECT USING (true);
CREATE POLICY "Autenticado cria categoria" ON public.categories FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

CREATE POLICY "Badges visíveis"            ON public.badges FOR SELECT USING (true);
CREATE POLICY "User badges visíveis"       ON public.user_badges FOR SELECT USING (true);
CREATE POLICY "Sistema insere user badges" ON public.user_badges FOR INSERT WITH CHECK (true);

-- ============================================================
-- Função: make_prediction (substituiu place_bet)
-- ============================================================
CREATE OR REPLACE FUNCTION public.make_prediction(
  p_user_id   UUID,
  p_event_id  UUID,
  p_option_id UUID
) RETURNS VOID AS $$
BEGIN
  IF (SELECT status FROM public.events WHERE id = p_event_id) != 'open' THEN
    RAISE EXCEPTION 'Evento não está aberto para previsões';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.options WHERE id = p_option_id AND event_id = p_event_id
  ) THEN
    RAISE EXCEPTION 'Opção inválida para este evento';
  END IF;

  UPDATE public.options
  SET prediction_count = prediction_count + 1
  WHERE id = p_option_id;

  INSERT INTO public.bets (user_id, event_id, option_id)
  VALUES (p_user_id, p_event_id, p_option_id);

  -- Badge primeira previsão
  INSERT INTO public.user_badges (user_id, badge_id)
  VALUES (p_user_id, 'first_prediction')
  ON CONFLICT (user_id, badge_id) DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- Função: resolve_event (atualizada com badges de acerto)
-- ============================================================
CREATE OR REPLACE FUNCTION public.resolve_event(
  p_event_id          UUID,
  p_winning_option_id UUID
) RETURNS VOID AS $$
DECLARE
  v_bet       RECORD;
  v_hit_count INTEGER;
BEGIN
  IF (SELECT created_by FROM public.events WHERE id = p_event_id) != auth.uid() THEN
    RAISE EXCEPTION 'Apenas o criador pode resolver o evento';
  END IF;

  IF (SELECT status FROM public.events WHERE id = p_event_id) != 'open' THEN
    RAISE EXCEPTION 'Evento já foi resolvido';
  END IF;

  UPDATE public.events
  SET status = 'resolved', winning_option_id = p_winning_option_id
  WHERE id = p_event_id;

  FOR v_bet IN
    SELECT * FROM public.bets WHERE event_id = p_event_id
  LOOP
    IF v_bet.option_id = p_winning_option_id THEN
      UPDATE public.bets SET status = 'won' WHERE id = v_bet.id;

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
      UPDATE public.bets SET status = 'lost' WHERE id = v_bet.id;
    END IF;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- Migration v4: Sistema de admins por torneio
-- ============================================================

-- Tabela de admins
CREATE TABLE public.tournament_admins (
  tournament_id UUID REFERENCES public.tournaments(id) ON DELETE CASCADE NOT NULL,
  user_id       UUID REFERENCES public.profiles(id)    ON DELETE CASCADE NOT NULL,
  role          TEXT NOT NULL DEFAULT 'admin' CHECK (role IN ('owner', 'admin')),
  added_by      UUID REFERENCES public.profiles(id),
  added_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (tournament_id, user_id)
);

ALTER TABLE public.tournament_admins ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admins visíveis por todos" ON public.tournament_admins
  FOR SELECT USING (true);

CREATE POLICY "Owner adiciona admin" ON public.tournament_admins
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.tournament_admins ta
      WHERE ta.tournament_id = tournament_admins.tournament_id
        AND ta.user_id = auth.uid()
        AND ta.role = 'owner'
    )
  );

CREATE POLICY "Owner remove admin" ON public.tournament_admins
  FOR DELETE USING (
    role != 'owner'
    AND EXISTS (
      SELECT 1 FROM public.tournament_admins ta
      WHERE ta.tournament_id = tournament_admins.tournament_id
        AND ta.user_id = auth.uid()
        AND ta.role = 'owner'
    )
  );

-- Trigger: ao criar torneio, criador vira owner automaticamente
CREATE OR REPLACE FUNCTION public.handle_new_tournament()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.tournament_admins (tournament_id, user_id, role, added_by)
  VALUES (NEW.id, NEW.created_by, 'owner', NEW.created_by);
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_tournament_created
  AFTER INSERT ON public.tournaments
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_tournament();

-- Popula owners para torneios já existentes
INSERT INTO public.tournament_admins (tournament_id, user_id, role, added_by)
SELECT id, created_by, 'owner', created_by FROM public.tournaments
ON CONFLICT DO NOTHING;

-- ============================================================
-- Helper functions
-- ============================================================

CREATE OR REPLACE FUNCTION public.is_tournament_admin(p_tournament_id UUID)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.tournament_admins
    WHERE tournament_id = p_tournament_id AND user_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.is_tournament_owner(p_tournament_id UUID)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.tournament_admins
    WHERE tournament_id = p_tournament_id
      AND user_id = auth.uid()
      AND role = 'owner'
  );
$$;

-- Adiciona admin por email (só owner pode chamar)
CREATE OR REPLACE FUNCTION public.add_tournament_admin(
  p_tournament_id UUID,
  p_email         TEXT
) RETURNS TEXT AS $$
DECLARE
  v_user_id  UUID;
  v_username TEXT;
BEGIN
  IF NOT public.is_tournament_owner(p_tournament_id) THEN
    RAISE EXCEPTION 'Apenas o owner pode adicionar admins';
  END IF;

  SELECT id INTO v_user_id FROM auth.users WHERE email = p_email;
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuário não encontrado';
  END IF;

  INSERT INTO public.tournament_admins (tournament_id, user_id, role, added_by)
  VALUES (p_tournament_id, v_user_id, 'admin', auth.uid())
  ON CONFLICT (tournament_id, user_id) DO NOTHING;

  SELECT username INTO v_username FROM public.profiles WHERE id = v_user_id;
  RETURN COALESCE(v_username, p_email);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- Atualiza RLS: apenas admins criam/editam/deletam no torneio
-- ============================================================

DROP POLICY IF EXISTS "Autenticado cria eventos"   ON public.events;
DROP POLICY IF EXISTS "Criador atualiza evento"    ON public.events;
DROP POLICY IF EXISTS "Criador deleta evento"      ON public.events;
DROP POLICY IF EXISTS "Admin deleta evento"        ON public.events;
DROP POLICY IF EXISTS "Autenticado cria categoria" ON public.categories;
DROP POLICY IF EXISTS "Criador deleta categoria"   ON public.categories;
DROP POLICY IF EXISTS "Admin deleta categoria"     ON public.categories;
DROP POLICY IF EXISTS "Criador atualiza torneio"   ON public.tournaments;
DROP POLICY IF EXISTS "Criador deleta torneio"     ON public.tournaments;
DROP POLICY IF EXISTS "Owner deleta torneio"       ON public.tournaments;

CREATE POLICY "Admin cria evento" ON public.events FOR INSERT
  WITH CHECK (
    category_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.categories c
      JOIN public.tournament_admins ta ON ta.tournament_id = c.tournament_id
      WHERE c.id = events.category_id AND ta.user_id = auth.uid()
    )
  );

CREATE POLICY "Admin edita evento" ON public.events FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.categories c
      JOIN public.tournament_admins ta ON ta.tournament_id = c.tournament_id
      WHERE c.id = events.category_id AND ta.user_id = auth.uid()
    )
  );

CREATE POLICY "Admin deleta evento" ON public.events FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.categories c
      JOIN public.tournament_admins ta ON ta.tournament_id = c.tournament_id
      WHERE c.id = events.category_id AND ta.user_id = auth.uid()
    )
  );

CREATE POLICY "Admin cria categoria" ON public.categories FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.tournament_admins
      WHERE tournament_id = categories.tournament_id AND user_id = auth.uid()
    )
  );

CREATE POLICY "Admin deleta categoria" ON public.categories FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.tournament_admins
      WHERE tournament_id = categories.tournament_id AND user_id = auth.uid()
    )
  );

CREATE POLICY "Owner atualiza torneio" ON public.tournaments FOR UPDATE
  USING (public.is_tournament_owner(id));

CREATE POLICY "Owner deleta torneio" ON public.tournaments FOR DELETE
  USING (public.is_tournament_owner(id));

-- ============================================================
-- resolve_event: qualquer admin do torneio pode resolver
-- ============================================================
CREATE OR REPLACE FUNCTION public.resolve_event(
  p_event_id          UUID,
  p_winning_option_id UUID
) RETURNS VOID AS $$
DECLARE
  v_bet           RECORD;
  v_hit_count     INTEGER;
  v_tournament_id UUID;
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

  UPDATE public.events
  SET status = 'resolved', winning_option_id = p_winning_option_id
  WHERE id = p_event_id;

  FOR v_bet IN SELECT * FROM public.bets WHERE event_id = p_event_id
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

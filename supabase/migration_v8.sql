-- ============================================================
-- Migration v8: tournament_members + aprovação de participantes
-- ============================================================

-- Tabela de membros do torneio
CREATE TABLE public.tournament_members (
  tournament_id UUID REFERENCES public.tournaments(id) ON DELETE CASCADE NOT NULL,
  user_id       UUID REFERENCES public.profiles(id)    ON DELETE CASCADE NOT NULL,
  status        TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  joined_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  approved_at   TIMESTAMPTZ,
  approved_by   UUID REFERENCES public.profiles(id),
  PRIMARY KEY (tournament_id, user_id)
);

ALTER TABLE public.tournament_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Membros visíveis por todos"
  ON public.tournament_members FOR SELECT USING (true);

CREATE POLICY "Usuário solicita entrada"
  ON public.tournament_members FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admin atualiza status"
  ON public.tournament_members FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.tournament_admins
      WHERE tournament_id = tournament_members.tournament_id
        AND user_id = auth.uid()
    )
  );

-- ============================================================
-- Função: join_tournament
-- Usuário entra no torneio (valida voting_code se existir)
-- ============================================================
CREATE OR REPLACE FUNCTION public.join_tournament(
  p_tournament_id UUID,
  p_voting_code   TEXT DEFAULT NULL
) RETURNS TEXT AS $$
DECLARE
  v_code TEXT;
  v_exists BOOLEAN;
BEGIN
  -- verifica se já é membro
  SELECT EXISTS (
    SELECT 1 FROM public.tournament_members
    WHERE tournament_id = p_tournament_id AND user_id = auth.uid()
  ) INTO v_exists;

  IF v_exists THEN
    RAISE EXCEPTION 'Você já solicitou entrada neste torneio';
  END IF;

  -- valida código se o torneio exigir
  SELECT voting_code INTO v_code FROM public.tournaments WHERE id = p_tournament_id;

  IF v_code IS NOT NULL AND v_code != '' THEN
    IF p_voting_code IS NULL OR upper(trim(p_voting_code)) != upper(trim(v_code)) THEN
      RAISE EXCEPTION 'Código de acesso inválido';
    END IF;
  END IF;

  -- admins entram já aprovados
  IF EXISTS (
    SELECT 1 FROM public.tournament_admins
    WHERE tournament_id = p_tournament_id AND user_id = auth.uid()
  ) THEN
    INSERT INTO public.tournament_members (tournament_id, user_id, status, approved_at, approved_by)
    VALUES (p_tournament_id, auth.uid(), 'approved', NOW(), auth.uid());
    RETURN 'approved';
  END IF;

  INSERT INTO public.tournament_members (tournament_id, user_id, status)
  VALUES (p_tournament_id, auth.uid(), 'pending');
  RETURN 'pending';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- Função: approve_member / reject_member
-- ============================================================
CREATE OR REPLACE FUNCTION public.approve_member(
  p_tournament_id UUID,
  p_user_id       UUID
) RETURNS VOID AS $$
BEGIN
  IF NOT public.is_tournament_admin(p_tournament_id) THEN
    RAISE EXCEPTION 'Apenas admins podem aprovar membros';
  END IF;

  UPDATE public.tournament_members
  SET status = 'approved', approved_at = NOW(), approved_by = auth.uid()
  WHERE tournament_id = p_tournament_id AND user_id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.reject_member(
  p_tournament_id UUID,
  p_user_id       UUID
) RETURNS VOID AS $$
BEGIN
  IF NOT public.is_tournament_admin(p_tournament_id) THEN
    RAISE EXCEPTION 'Apenas admins podem rejeitar membros';
  END IF;

  UPDATE public.tournament_members
  SET status = 'rejected'
  WHERE tournament_id = p_tournament_id AND user_id = p_user_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Popula membros aprovados para torneios existentes
-- (todos que já votaram ou são admins viram membros aprovados)
INSERT INTO public.tournament_members (tournament_id, user_id, status, approved_at)
SELECT DISTINCT c.tournament_id, b.user_id, 'approved', NOW()
FROM public.bets b
JOIN public.events e ON e.id = b.event_id
JOIN public.categories c ON c.id = e.category_id
WHERE c.tournament_id IS NOT NULL
ON CONFLICT DO NOTHING;

INSERT INTO public.tournament_members (tournament_id, user_id, status, approved_at)
SELECT tournament_id, user_id, 'approved', NOW()
FROM public.tournament_admins
ON CONFLICT DO NOTHING;

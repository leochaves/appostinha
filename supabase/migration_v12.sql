-- ============================================================
-- Migration v12: Admins entram automaticamente como membros
--                aprovados com moedas (se modo coin)
-- ============================================================

-- ============================================================
-- Trigger atualizado: ao criar torneio, owner vira membro aprovado
-- ============================================================
CREATE OR REPLACE FUNCTION public.handle_new_tournament()
RETURNS TRIGGER AS $$
BEGIN
  -- Adiciona como owner em tournament_admins (já existia)
  INSERT INTO public.tournament_admins (tournament_id, user_id, role, added_by)
  VALUES (NEW.id, NEW.created_by, 'owner', NEW.created_by)
  ON CONFLICT DO NOTHING;

  -- Adiciona como membro aprovado em tournament_members
  -- Moedas serão atribuídas AGORA pois o torneio já tem mode/initial_coins
  INSERT INTO public.tournament_members
    (tournament_id, user_id, status, approved_at, approved_by, coins, initial_coins)
  VALUES (
    NEW.id,
    NEW.created_by,
    'approved',
    NOW(),
    NEW.created_by,
    CASE WHEN NEW.mode = 'coin' THEN NEW.initial_coins ELSE 0 END,
    CASE WHEN NEW.mode = 'coin' THEN NEW.initial_coins ELSE 0 END
  )
  ON CONFLICT DO NOTHING;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- add_tournament_admin atualizado:
-- ao adicionar admin, também entra como membro aprovado com moedas
-- ============================================================
CREATE OR REPLACE FUNCTION public.add_tournament_admin(
  p_tournament_id UUID,
  p_email         TEXT
) RETURNS TEXT AS $$
DECLARE
  v_user_id       UUID;
  v_username      TEXT;
  v_mode          TEXT;
  v_initial_coins INTEGER;
BEGIN
  IF NOT public.is_tournament_owner(p_tournament_id) THEN
    RAISE EXCEPTION 'Apenas o owner pode adicionar admins';
  END IF;

  SELECT id INTO v_user_id FROM auth.users WHERE email = p_email;
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuário não encontrado';
  END IF;

  -- Adiciona em tournament_admins
  INSERT INTO public.tournament_admins (tournament_id, user_id, role, added_by)
  VALUES (p_tournament_id, v_user_id, 'admin', auth.uid())
  ON CONFLICT (tournament_id, user_id) DO NOTHING;

  -- Busca modo do torneio
  SELECT mode, initial_coins
  INTO v_mode, v_initial_coins
  FROM public.tournaments
  WHERE id = p_tournament_id;

  -- Adiciona como membro aprovado (com moedas se modo coin)
  INSERT INTO public.tournament_members
    (tournament_id, user_id, status, approved_at, approved_by, coins, initial_coins)
  VALUES (
    p_tournament_id,
    v_user_id,
    'approved',
    NOW(),
    auth.uid(),
    CASE WHEN v_mode = 'coin' THEN v_initial_coins ELSE 0 END,
    CASE WHEN v_mode = 'coin' THEN v_initial_coins ELSE 0 END
  )
  ON CONFLICT (tournament_id, user_id) DO NOTHING;
  -- ON CONFLICT DO NOTHING: se já era membro (pending/rejected/approved),
  -- não sobrescreve — admin não perde saldo existente

  SELECT username INTO v_username FROM public.profiles WHERE id = v_user_id;
  RETURN COALESCE(v_username, p_email);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- Retroativo: owners e admins existentes que ainda não são membros
-- entram como aprovados (sem moedas — não sabemos o initial_coins
-- que era válido na época; admin pode ajustar via add_coins)
-- ============================================================
INSERT INTO public.tournament_members
  (tournament_id, user_id, status, approved_at, approved_by)
SELECT
  ta.tournament_id,
  ta.user_id,
  'approved',
  NOW(),
  ta.user_id
FROM public.tournament_admins ta
WHERE NOT EXISTS (
  SELECT 1 FROM public.tournament_members tm
  WHERE tm.tournament_id = ta.tournament_id
    AND tm.user_id = ta.user_id
)
ON CONFLICT DO NOTHING;

-- ============================================================
-- RESET COMPLETO DE INTERAÇÕES
-- Preserva: torneios, categorias, eventos, opções, usuários
-- Apaga: votos, badges
-- ============================================================

BEGIN;

-- 1. Deleta todos os votos
DELETE FROM public.bets;

-- 2. Zera a contagem de votos nas opções
UPDATE public.options SET prediction_count = 0;

-- 3. Reabre todos os eventos (desfaz resolução)
UPDATE public.events
SET status = 'open', winning_option_id = NULL;

-- 4. Deleta todos os badges dos usuários
DELETE FROM public.user_badges;

COMMIT;

-- Conferência
SELECT
  (SELECT COUNT(*) FROM public.bets)        AS votos_restantes,
  (SELECT COUNT(*) FROM public.user_badges) AS badges_restantes,
  (SELECT COUNT(*) FROM public.events WHERE status != 'open') AS eventos_nao_abertos;

-- ============================================================
-- RESET COMPLETO DE INTERAÇÕES
-- Preserva: torneios, categorias, eventos, opções, usuários
-- Apaga: votos, badges, saldo restaurado para 1000
-- ============================================================
-- CUIDADO: irreversível! Faça backup antes se necessário.
-- ============================================================

BEGIN;

-- 1. Deleta todos os votos
DELETE FROM public.bets;

-- 2. Zera os pools das opções
UPDATE public.options SET total_pool = 0;

-- 3. Reabre todos os eventos (desfaz resolução)
UPDATE public.events
SET status = 'open', winning_option_id = NULL;

-- 4. Deleta todos os badges dos usuários
DELETE FROM public.user_badges;

-- 5. Restaura saldo de todos os usuários para 1000
UPDATE public.profiles SET balance = 1000;

COMMIT;

-- Conferência
SELECT
  (SELECT COUNT(*) FROM public.bets)        AS votos_restantes,
  (SELECT COUNT(*) FROM public.user_badges) AS badges_restantes,
  (SELECT COUNT(*) FROM public.events WHERE status != 'open') AS eventos_nao_abertos,
  (SELECT MIN(balance) FROM public.profiles) AS menor_saldo,
  (SELECT MAX(balance) FROM public.profiles) AS maior_saldo;

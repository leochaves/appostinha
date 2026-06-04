-- Limpa todos os votos e restaura o saldo dos usuários
-- CUIDADO: irreversível!

BEGIN;

-- 1. Restaura o saldo de cada usuário (soma das apostas feitas)
UPDATE profiles p
SET balance = balance + coalesce((
  SELECT SUM(b.amount)
  FROM bets b
  WHERE b.user_id = p.id
), 0);

-- 2. Zera contagem de votos nas opções
UPDATE bet_options SET prediction_count = 0;

-- 3. Deleta todos os votos
DELETE FROM bets;

-- 4. Reabre eventos que estavam resolvidos (opcional — comente se não quiser)
-- UPDATE events SET status = 'open', winning_option_id = NULL WHERE status = 'resolved';

COMMIT;

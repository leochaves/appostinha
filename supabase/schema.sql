-- ============================================================
-- Apostinha - Schema SQL
-- Cole este arquivo no SQL Editor do seu projeto Supabase
-- ============================================================

-- Tabela de perfis (extende auth.users)
CREATE TABLE public.profiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  username TEXT,
  balance INTEGER NOT NULL DEFAULT 1000,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Tabela de eventos
CREATE TABLE public.events (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  title TEXT NOT NULL,
  description TEXT,
  created_by UUID REFERENCES public.profiles(id) NOT NULL,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed', 'resolved')),
  winning_option_id UUID,
  closes_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Tabela de opções de aposta
CREATE TABLE public.options (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  event_id UUID REFERENCES public.events(id) ON DELETE CASCADE NOT NULL,
  title TEXT NOT NULL,
  total_pool INTEGER NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- FK para a opção vencedora (criada depois de options)
ALTER TABLE public.events
  ADD CONSTRAINT fk_winning_option
  FOREIGN KEY (winning_option_id) REFERENCES public.options(id);

-- Tabela de apostas
CREATE TABLE public.bets (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES public.profiles(id) NOT NULL,
  event_id UUID REFERENCES public.events(id) NOT NULL,
  option_id UUID REFERENCES public.options(id) NOT NULL,
  amount INTEGER NOT NULL CHECK (amount > 0),
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'won', 'lost')),
  payout INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id, event_id)  -- uma aposta por evento por usuário
);

-- ============================================================
-- Row Level Security
-- ============================================================

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.events   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.options  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bets     ENABLE ROW LEVEL SECURITY;

-- Profiles
CREATE POLICY "Profiles visíveis por todos"       ON public.profiles FOR SELECT USING (true);
CREATE POLICY "Usuário insere próprio perfil"      ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "Usuário atualiza próprio perfil"    ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Events
CREATE POLICY "Eventos visíveis por todos"         ON public.events FOR SELECT USING (true);
CREATE POLICY "Autenticado cria eventos"           ON public.events FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "Criador atualiza evento"            ON public.events FOR UPDATE USING (auth.uid() = created_by);

-- Options
CREATE POLICY "Opções visíveis por todos"          ON public.options FOR SELECT USING (true);
CREATE POLICY "Autenticado cria opções"            ON public.options FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);
CREATE POLICY "Pool de opções pode ser atualizado" ON public.options FOR UPDATE USING (true);

-- Bets
CREATE POLICY "Apostas visíveis por todos"         ON public.bets FOR SELECT USING (true);
CREATE POLICY "Usuário cria própria aposta"        ON public.bets FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Sistema atualiza apostas"           ON public.bets FOR UPDATE USING (true);

-- ============================================================
-- Trigger: cria perfil automaticamente ao registrar
-- ============================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, username)
  VALUES (NEW.id, split_part(NEW.email, '@', 1));
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================================
-- Função: place_bet (operação atômica)
-- ============================================================

CREATE OR REPLACE FUNCTION public.place_bet(
  p_user_id    UUID,
  p_event_id   UUID,
  p_option_id  UUID,
  p_amount     INTEGER
) RETURNS VOID AS $$
BEGIN
  -- Verificações
  IF (SELECT balance FROM public.profiles WHERE id = p_user_id) < p_amount THEN
    RAISE EXCEPTION 'Saldo insuficiente';
  END IF;

  IF (SELECT status FROM public.events WHERE id = p_event_id) != 'open' THEN
    RAISE EXCEPTION 'Evento não está aberto para apostas';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.options WHERE id = p_option_id AND event_id = p_event_id
  ) THEN
    RAISE EXCEPTION 'Opção inválida para este evento';
  END IF;

  -- Deduz saldo
  UPDATE public.profiles SET balance = balance - p_amount WHERE id = p_user_id;

  -- Adiciona ao pool da opção
  UPDATE public.options SET total_pool = total_pool + p_amount WHERE id = p_option_id;

  -- Registra a aposta
  INSERT INTO public.bets (user_id, event_id, option_id, amount)
  VALUES (p_user_id, p_event_id, p_option_id, p_amount);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- Função: resolve_event (paga vencedores proporcionalmente)
-- ============================================================

CREATE OR REPLACE FUNCTION public.resolve_event(
  p_event_id          UUID,
  p_winning_option_id UUID
) RETURNS VOID AS $$
DECLARE
  v_total_pool    INTEGER;
  v_winning_pool  INTEGER;
  v_bet           RECORD;
  v_payout        INTEGER;
BEGIN
  -- Apenas o criador pode resolver
  IF (SELECT created_by FROM public.events WHERE id = p_event_id) != auth.uid() THEN
    RAISE EXCEPTION 'Apenas o criador pode resolver o evento';
  END IF;

  IF (SELECT status FROM public.events WHERE id = p_event_id) != 'open' THEN
    RAISE EXCEPTION 'Evento já foi resolvido';
  END IF;

  -- Pool total do evento
  SELECT COALESCE(SUM(total_pool), 0) INTO v_total_pool
  FROM public.options WHERE event_id = p_event_id;

  -- Pool da opção vencedora
  SELECT total_pool INTO v_winning_pool
  FROM public.options WHERE id = p_winning_option_id;

  -- Atualiza status do evento
  UPDATE public.events
  SET status = 'resolved', winning_option_id = p_winning_option_id
  WHERE id = p_event_id;

  -- Se alguém apostou na opção vencedora, paga proporcionalmente
  IF v_winning_pool > 0 THEN
    FOR v_bet IN
      SELECT * FROM public.bets
      WHERE event_id = p_event_id AND option_id = p_winning_option_id
    LOOP
      v_payout := FLOOR(v_bet.amount::FLOAT / v_winning_pool::FLOAT * v_total_pool::FLOAT);
      UPDATE public.bets SET status = 'won', payout = v_payout WHERE id = v_bet.id;
      UPDATE public.profiles SET balance = balance + v_payout WHERE id = v_bet.user_id;
    END LOOP;
  END IF;

  -- Marca apostas perdedoras
  UPDATE public.bets
  SET status = 'lost'
  WHERE event_id = p_event_id AND option_id != p_winning_option_id AND status = 'pending';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

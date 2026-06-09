-- ============================================================
-- Seed: Projeto Polvo
-- 40 usuários · 1 torneio coin (Zen) · 2 categorias · 10 eventos · apostas aleatórias
--
-- Login: seed01@apostinha.test até seed40@apostinha.test
-- Senha: 123123123
-- seed01 é o dono do torneio (admin)
-- ============================================================

DO $$
DECLARE
  v_tid   UUID := gen_random_uuid();  -- torneio
  v_cm    UUID := gen_random_uuid();  -- categoria Mata Mata
  v_cg    UUID := gen_random_uuid();  -- categoria Geral
  v_owner UUID;
  v_uid   UUID;
  v_eid   UUID;
  v_oid   UUID;
  v_amt   INT;
  v_bal   INT;
  i       INT;
  INITIAL CONSTANT INT := 1000;
BEGIN

  CREATE TEMP TABLE _users  (id UUID, idx INT) ON COMMIT DROP;
  CREATE TEMP TABLE _events (id UUID)           ON COMMIT DROP;

  -- ── 40 usuários ──────────────────────────────────────────────
  FOR i IN 1..40 LOOP
    v_uid := gen_random_uuid();

    INSERT INTO auth.users (
      id, instance_id, aud, role,
      email, encrypted_password, email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at,
      -- campos NOT NULL que o GoTrue exige como string vazia (não NULL)
      confirmation_token, recovery_token,
      email_change_token_new, email_change_token_current,
      email_change, phone_change, phone_change_token,
      reauthentication_token
    ) VALUES (
      v_uid,
      '00000000-0000-0000-0000-000000000000',
      'authenticated', 'authenticated',
      'seed' || lpad(i::text, 2, '0') || '@apostinha.test',
      crypt('123123123', gen_salt('bf')),
      NOW(),
      '{"provider":"email","providers":["email"]}', '{}',
      NOW(), NOW(),
      '', '', '', '', '', '', '', ''
    );

    -- identity necessária para login email/password em versões novas do Supabase
    INSERT INTO auth.identities (
      user_id, provider_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) VALUES (
      v_uid,
      'seed' || lpad(i::text,2,'0') || '@apostinha.test',
      jsonb_build_object('sub', v_uid::text, 'email', 'seed' || lpad(i::text,2,'0') || '@apostinha.test'),
      'email',
      NOW(), NOW(), NOW()
    ) ON CONFLICT DO NOTHING;

    -- upsert no profile (pode já existir via trigger on_auth_user_created)
    INSERT INTO public.profiles (id, username)
    VALUES (v_uid, 'Jogador ' || lpad(i::text, 2, '0'))
    ON CONFLICT (id) DO UPDATE SET username = EXCLUDED.username;

    INSERT INTO _users VALUES (v_uid, i);
    IF i = 1 THEN v_owner := v_uid; END IF;
  END LOOP;

  -- ── Torneio ──────────────────────────────────────────────────
  -- trigger handle_new_tournament → owner entra em admins + members com 1000 Zens
  INSERT INTO public.tournaments
    (id, name, description, created_by, mode, coin_name, initial_coins, status, slug)
  VALUES (
    v_tid,
    'Projeto Polvo',
    'Seed de testes. Admin: seed01@apostinha.test / 123123123',
    v_owner, 'coin', 'Zen', INITIAL, 'active', 'projeto-polvo'
  );

  -- ── Categorias ───────────────────────────────────────────────
  INSERT INTO public.categories (id, tournament_id, name, created_by) VALUES
    (v_cm, v_tid, 'Mata Mata', v_owner),
    (v_cg, v_tid, 'Geral',     v_owner);

  -- ── Eventos — Mata Mata (5) ───────────────────────────────────

  v_eid := gen_random_uuid();
  INSERT INTO public.events (id, title, category_id, created_by, status, points)
  VALUES (v_eid, 'Quem bust out primeiro?', v_cm, v_owner, 'open', 1);
  INSERT INTO _events VALUES (v_eid);
  INSERT INTO public.options (id, event_id, title) VALUES
    (gen_random_uuid(), v_eid, 'Felipe'),
    (gen_random_uuid(), v_eid, 'Bruno'),
    (gen_random_uuid(), v_eid, 'Camila'),
    (gen_random_uuid(), v_eid, 'Diego');

  v_eid := gen_random_uuid();
  INSERT INTO public.events (id, title, category_id, created_by, status, points)
  VALUES (v_eid, 'Quem chega ao money bubble?', v_cm, v_owner, 'open', 2);
  INSERT INTO _events VALUES (v_eid);
  INSERT INTO public.options (id, event_id, title) VALUES
    (gen_random_uuid(), v_eid, 'João'),
    (gen_random_uuid(), v_eid, 'Pedro'),
    (gen_random_uuid(), v_eid, 'Maria'),
    (gen_random_uuid(), v_eid, 'Carlos');

  v_eid := gen_random_uuid();
  INSERT INTO public.events (id, title, category_id, created_by, status, points)
  VALUES (v_eid, 'Quem tem o maior stack no break?', v_cm, v_owner, 'open', 2);
  INSERT INTO _events VALUES (v_eid);
  INSERT INTO public.options (id, event_id, title) VALUES
    (gen_random_uuid(), v_eid, 'Lucas'),
    (gen_random_uuid(), v_eid, 'Ana'),
    (gen_random_uuid(), v_eid, 'Ricardo'),
    (gen_random_uuid(), v_eid, 'Fernanda');

  v_eid := gen_random_uuid();
  INSERT INTO public.events (id, title, category_id, created_by, status, points)
  VALUES (v_eid, 'Quem vence o heads-up da mesa 2?', v_cm, v_owner, 'open', 3);
  INSERT INTO _events VALUES (v_eid);
  INSERT INTO public.options (id, event_id, title) VALUES
    (gen_random_uuid(), v_eid, 'Marcos'),
    (gen_random_uuid(), v_eid, 'Julia'),
    (gen_random_uuid(), v_eid, 'Rafael'),
    (gen_random_uuid(), v_eid, 'Beatriz');

  v_eid := gen_random_uuid();
  INSERT INTO public.events (id, title, category_id, created_by, status, points)
  VALUES (v_eid, 'Quem elimina mais jogadores?', v_cm, v_owner, 'open', 3);
  INSERT INTO _events VALUES (v_eid);
  INSERT INTO public.options (id, event_id, title) VALUES
    (gen_random_uuid(), v_eid, 'Rodrigo'),
    (gen_random_uuid(), v_eid, 'Amanda'),
    (gen_random_uuid(), v_eid, 'Thiago'),
    (gen_random_uuid(), v_eid, 'Bianca');

  -- ── Eventos — Geral (5) ───────────────────────────────────────

  v_eid := gen_random_uuid();
  INSERT INTO public.events (id, title, category_id, created_by, status, points)
  VALUES (v_eid, 'Campeão do torneio?', v_cg, v_owner, 'open', 5);
  INSERT INTO _events VALUES (v_eid);
  INSERT INTO public.options (id, event_id, title) VALUES
    (gen_random_uuid(), v_eid, 'João'),
    (gen_random_uuid(), v_eid, 'Pedro'),
    (gen_random_uuid(), v_eid, 'Carlos'),
    (gen_random_uuid(), v_eid, 'Lucas');

  v_eid := gen_random_uuid();
  INSERT INTO public.events (id, title, category_id, created_by, status, points)
  VALUES (v_eid, 'Quem vai a showdown mais vezes?', v_cg, v_owner, 'open', 2);
  INSERT INTO _events VALUES (v_eid);
  INSERT INTO public.options (id, event_id, title) VALUES
    (gen_random_uuid(), v_eid, 'Felipe'),
    (gen_random_uuid(), v_eid, 'Bruno'),
    (gen_random_uuid(), v_eid, 'Maria'),
    (gen_random_uuid(), v_eid, 'Ricardo');

  v_eid := gen_random_uuid();
  INSERT INTO public.events (id, title, category_id, created_by, status, points)
  VALUES (v_eid, 'Melhor mão do torneio?', v_cg, v_owner, 'open', 3);
  INSERT INTO _events VALUES (v_eid);
  INSERT INTO public.options (id, event_id, title) VALUES
    (gen_random_uuid(), v_eid, 'Royal Flush'),
    (gen_random_uuid(), v_eid, 'Straight Flush'),
    (gen_random_uuid(), v_eid, 'Quatro Ases'),
    (gen_random_uuid(), v_eid, 'Full House');

  v_eid := gen_random_uuid();
  INSERT INTO public.events (id, title, category_id, created_by, status, points)
  VALUES (v_eid, 'Quem faz mais blefes?', v_cg, v_owner, 'open', 2);
  INSERT INTO _events VALUES (v_eid);
  INSERT INTO public.options (id, event_id, title) VALUES
    (gen_random_uuid(), v_eid, 'Amanda'),
    (gen_random_uuid(), v_eid, 'Thiago'),
    (gen_random_uuid(), v_eid, 'Rodrigo'),
    (gen_random_uuid(), v_eid, 'Fernanda');

  v_eid := gen_random_uuid();
  INSERT INTO public.events (id, title, category_id, created_by, status, points)
  VALUES (v_eid, 'Duração total do torneio?', v_cg, v_owner, 'open', 1);
  INSERT INTO _events VALUES (v_eid);
  INSERT INTO public.options (id, event_id, title) VALUES
    (gen_random_uuid(), v_eid, 'Menos de 4h'),
    (gen_random_uuid(), v_eid, 'Entre 4h e 6h'),
    (gen_random_uuid(), v_eid, 'Entre 6h e 8h'),
    (gen_random_uuid(), v_eid, 'Mais de 8h');

  -- ── Membros (seed02–seed40; seed01 já foi pelo trigger) ──────
  INSERT INTO public.tournament_members
    (tournament_id, user_id, status, approved_at, approved_by, coins, initial_coins)
  SELECT v_tid, id, 'approved', NOW(), v_owner, INITIAL, INITIAL
  FROM _users
  WHERE idx > 1
  ON CONFLICT DO NOTHING;

  -- ── Apostas aleatórias ───────────────────────────────────────
  -- Cada usuário aposta em 5–8 eventos aleatórios
  FOR v_uid IN (SELECT id FROM _users) LOOP
    FOR v_eid IN (
      SELECT id FROM _events ORDER BY random()
      LIMIT (5 + floor(random() * 4)::int)
    ) LOOP
      -- opção aleatória do evento
      SELECT id INTO v_oid
      FROM public.options
      WHERE event_id = v_eid
      ORDER BY random() LIMIT 1;

      -- valor entre 50 e 200
      v_amt := 50 + floor(random() * 151)::int;

      -- saldo atual do membro
      SELECT coins INTO v_bal
      FROM public.tournament_members
      WHERE tournament_id = v_tid AND user_id = v_uid;

      IF v_bal >= v_amt THEN
        INSERT INTO public.bets (user_id, event_id, option_id, status, amount)
        VALUES (v_uid, v_eid, v_oid, 'pending', v_amt);

        UPDATE public.options
        SET coin_pool = coin_pool + v_amt
        WHERE id = v_oid;

        UPDATE public.tournament_members
        SET coins = coins - v_amt
        WHERE tournament_id = v_tid AND user_id = v_uid;
      END IF;
    END LOOP;
  END LOOP;

  RAISE NOTICE 'Seed concluído! Torneio: % | Usuários: seed01–seed40@apostinha.test | Senha: 123123123', v_tid;

END;
$$;

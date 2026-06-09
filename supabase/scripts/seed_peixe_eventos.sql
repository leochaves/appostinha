-- ============================================================
-- Seed: Poker do Peixe — Eventos 2026
-- Apenas eventos e opções. Nenhum usuário criado.
-- Troque SEU-USER-ID-AQUI pelo seu UUID antes de rodar.
-- ============================================================

DO $$
DECLARE
  v_admin UUID := 'b22ff99b-dcf9-4669-af11-ab4125c80008';
  v_tid      UUID := gen_random_uuid();
  v_cranking UUID := gen_random_uuid();
  v_cjun     UUID := gen_random_uuid();
  v_eid      UUID;
BEGIN

  -- ── Torneio ──────────────────────────────────────────────────
  INSERT INTO public.tournaments
    (id, name, description, created_by, mode, coin_name, initial_coins, status, slug)
  VALUES (
    v_tid,
    'Poker do Peixe 2026',
    'Torneio oficial do grupo. Classificação e memes.',
    v_admin, 'coin', 'Fi$hi', 1000, 'active', 'poker-do-peixe-2026'
  );

  -- admin entra como owner
  INSERT INTO public.tournament_admins (tournament_id, user_id, role)
  VALUES (v_tid, v_admin, 'owner')
  ON CONFLICT DO NOTHING;

  INSERT INTO public.tournament_members (tournament_id, user_id, status, approved_at, approved_by)
  VALUES (v_tid, v_admin, 'approved', NOW(), v_admin)
  ON CONFLICT DO NOTHING;

  -- ── Categorias ───────────────────────────────────────────────
  INSERT INTO public.categories (id, tournament_id, name, created_by) VALUES
    (v_cranking, v_tid, 'Ranking 2026',    v_admin),
    (v_cjun,     v_tid, 'Rodada Jun/2026', v_admin);

  -- ════════════════════════════════════════════════════════════
  -- MEMES & TRADIÇÕES
  -- ════════════════════════════════════════════════════════════

  -- Camargos: kamikaze
  v_eid := gen_random_uuid();
  INSERT INTO public.events (id, title, category_id, created_by, status, points)
  VALUES (v_eid, 'Camargos vai all-in nas primeiras 3 mãos?', v_cranking, v_admin, 'open', 2);
  INSERT INTO public.options (event_id, title) VALUES
    (v_eid, 'Sim, claro 💣'),
    (v_eid, 'Não resiste até a 5ª'),
    (v_eid, 'Surpreende e joga tight');

  -- André: mesa principal
  v_eid := gen_random_uuid();
  INSERT INTO public.events (id, title, category_id, created_by, status, points)
  VALUES (v_eid, 'André vai sentar na mesa principal de novo?', v_cranking, v_admin, 'open', 1);
  INSERT INTO public.options (event_id, title) VALUES
    (v_eid, 'Óbvio, já reservou a cadeira 🪑'),
    (v_eid, 'Dessa vez vai na mesa 2'),
    (v_eid, 'Chega atrasado e pega o que sobrar');

  -- Alexandre: nunca ganhou nada
  v_eid := gen_random_uuid();
  INSERT INTO public.events (id, title, category_id, created_by, status, points)
  VALUES (v_eid, 'Alexandre vai ganhar alguma coisa em 2026?', v_cranking, v_admin, 'open', 3);
  INSERT INTO public.options (event_id, title) VALUES
    (v_eid, 'Sim, ano da virada! 🍀'),
    (v_eid, 'Não, a seca continua'),
    (v_eid, 'Ganha só o prêmio de presença');

  -- Leo: apelou como dealer
  v_eid := gen_random_uuid();
  INSERT INTO public.events (id, title, category_id, created_by, status, points)
  VALUES (v_eid, 'Leo vai apelar da mesa de novo no próximo torneio?', v_cranking, v_admin, 'open', 2);
  INSERT INTO public.options (event_id, title) VALUES
    (v_eid, 'Sim, já está estudando o regulamento 📋'),
    (v_eid, 'Não, aprendeu a lição'),
    (v_eid, 'Não apela, mas reclama muito');

  -- Ricardo: último a chegar, primeiro a ir
  v_eid := gen_random_uuid();
  INSERT INTO public.events (id, title, category_id, created_by, status, points)
  VALUES (v_eid, 'Ricardo chega atrasado E sai antes da hora?', v_cranking, v_admin, 'open', 2);
  INSERT INTO public.options (event_id, title) VALUES
    (v_eid, 'Sim, double combo 🏃'),
    (v_eid, 'Chega atrasado mas fica até o fim'),
    (v_eid, 'Chega na hora por uma vez na vida');

  -- Leandro: whisky
  v_eid := gen_random_uuid();
  INSERT INTO public.events (id, title, category_id, created_by, status, points)
  VALUES (v_eid, 'Leandro traz o whisky no próximo torneio?', v_cranking, v_admin, 'open', 1);
  INSERT INTO public.options (event_id, title) VALUES
    (v_eid, 'Sim, tradição é tradição 🥃'),
    (v_eid, 'Esquece em casa'),
    (v_eid, 'Traz mas não divide');

  -- ════════════════════════════════════════════════════════════
  -- RANKING 2026
  -- ════════════════════════════════════════════════════════════

  -- Campeão geral (João lidera com 80pts)
  v_eid := gen_random_uuid();
  INSERT INTO public.events (id, title, category_id, created_by, status, points)
  VALUES (v_eid, 'Quem vai ser campeão geral de 2026?', v_cranking, v_admin, 'open', 5);
  INSERT INTO public.options (event_id, title) VALUES
    (v_eid, 'João 👑 (80pts)'),
    (v_eid, 'Beto (62pts)'),
    (v_eid, 'Daniel Melo (53pts)'),
    (v_eid, 'Zé Milton (53pts)'),
    (v_eid, 'André (49pts)'),
    (v_eid, 'Outro');

  -- João segura a liderança?
  v_eid := gen_random_uuid();
  INSERT INTO public.events (id, title, category_id, created_by, status, points)
  VALUES (v_eid, 'João termina o ano em 1º lugar?', v_cranking, v_admin, 'open', 3);
  INSERT INTO public.options (event_id, title) VALUES
    (v_eid, 'Sim, domínio total 🔒'),
    (v_eid, 'Não, Beto vira'),
    (v_eid, 'Não, surpresa do pelotão');

  -- Alguém ultrapassa João ainda em 2026?
  v_eid := gen_random_uuid();
  INSERT INTO public.events (id, title, category_id, created_by, status, points)
  VALUES (v_eid, 'Quem tem mais chances de ultrapassar João?', v_cranking, v_admin, 'open', 3);
  INSERT INTO public.options (event_id, title) VALUES
    (v_eid, 'Beto'),
    (v_eid, 'Daniel Melo'),
    (v_eid, 'Zé Milton'),
    (v_eid, 'André'),
    (v_eid, 'Ninguém chega perto');

  -- Alexandre termina no top 20?
  v_eid := gen_random_uuid();
  INSERT INTO public.events (id, title, category_id, created_by, status, points)
  VALUES (v_eid, 'Alexandre termina o ranking em qual faixa?', v_cranking, v_admin, 'open', 2);
  INSERT INTO public.options (event_id, title) VALUES
    (v_eid, 'Top 10 (virada histórica)'),
    (v_eid, 'Entre 11º e 20º'),
    (v_eid, 'Abaixo do 20º — status quo'),
    (v_eid, 'Nem aparece no ranking');

  -- ════════════════════════════════════════════════════════════
  -- RODADA JUN/2026
  -- ════════════════════════════════════════════════════════════

  -- Quem vence?
  v_eid := gen_random_uuid();
  INSERT INTO public.events (id, title, category_id, created_by, status, points)
  VALUES (v_eid, 'Quem vence a rodada de junho?', v_cjun, v_admin, 'open', 5);
  INSERT INTO public.options (event_id, title) VALUES
    (v_eid, 'João'),
    (v_eid, 'Beto'),
    (v_eid, 'Daniel Melo'),
    (v_eid, 'Zé Milton'),
    (v_eid, 'André'),
    (v_eid, 'Daniel Tibo'),
    (v_eid, 'Zebra');

  -- Quem bust out primeiro?
  v_eid := gen_random_uuid();
  INSERT INTO public.events (id, title, category_id, created_by, status, points)
  VALUES (v_eid, 'Quem vai bust out primeiro?', v_cjun, v_admin, 'open', 3);
  INSERT INTO public.options (event_id, title) VALUES
    (v_eid, 'Camargos 💣'),
    (v_eid, 'Alexandre'),
    (v_eid, 'Ricardo'),
    (v_eid, 'Reinaldo'),
    (v_eid, 'Outro');

  -- Quantos participantes?
  v_eid := gen_random_uuid();
  INSERT INTO public.events (id, title, category_id, created_by, status, points)
  VALUES (v_eid, 'Quantos jogadores vão comparecer em junho?', v_cjun, v_admin, 'open', 1);
  INSERT INTO public.options (event_id, title) VALUES
    (v_eid, 'Menos de 15'),
    (v_eid, 'Entre 15 e 20'),
    (v_eid, 'Entre 21 e 25'),
    (v_eid, 'Mais de 25');

  -- Duração
  v_eid := gen_random_uuid();
  INSERT INTO public.events (id, title, category_id, created_by, status, points)
  VALUES (v_eid, 'Duração da rodada de junho?', v_cjun, v_admin, 'open', 1);
  INSERT INTO public.options (event_id, title) VALUES
    (v_eid, 'Menos de 4h'),
    (v_eid, 'Entre 4h e 6h'),
    (v_eid, 'Entre 6h e 8h'),
    (v_eid, 'Mais de 8h (modo resistência)');

  -- Ricardo vai chegar atrasado?
  v_eid := gen_random_uuid();
  INSERT INTO public.events (id, title, category_id, created_by, status, points)
  VALUES (v_eid, 'Ricardo chega depois que as cartas já foram distribuídas?', v_cjun, v_admin, 'open', 1);
  INSERT INTO public.options (event_id, title) VALUES
    (v_eid, 'Sim, clássico 🕐'),
    (v_eid, 'Surpreende e chega no horário');

  -- Camargos bust out antes de 1h?
  v_eid := gen_random_uuid();
  INSERT INTO public.events (id, title, category_id, created_by, status, points)
  VALUES (v_eid, 'Camargos bust out na primeira hora?', v_cjun, v_admin, 'open', 2);
  INSERT INTO public.options (event_id, title) VALUES
    (v_eid, 'Sim, foi na primeira mão 💥'),
    (v_eid, 'Não, chegou na metade'),
    (v_eid, 'Fez ITM — milagre do mês');

  RAISE NOTICE 'Seed Peixe concluído! Torneio: % | Slug: poker-do-peixe-2026', v_tid;

END;
$$;

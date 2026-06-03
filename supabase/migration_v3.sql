-- ============================================================
-- Migration v3: Delete cascades + políticas de delete/edit
-- ============================================================

-- Recria FK de bets com CASCADE para permitir deletar eventos
ALTER TABLE public.bets DROP CONSTRAINT IF EXISTS bets_event_id_fkey;
ALTER TABLE public.bets ADD CONSTRAINT bets_event_id_fkey
  FOREIGN KEY (event_id) REFERENCES public.events(id) ON DELETE CASCADE;

ALTER TABLE public.bets DROP CONSTRAINT IF EXISTS bets_option_id_fkey;
ALTER TABLE public.bets ADD CONSTRAINT bets_option_id_fkey
  FOREIGN KEY (option_id) REFERENCES public.options(id) ON DELETE CASCADE;

-- Políticas de DELETE
CREATE POLICY "Criador deleta evento"    ON public.events     FOR DELETE USING (auth.uid() = created_by);
CREATE POLICY "Criador deleta torneio"   ON public.tournaments FOR DELETE USING (auth.uid() = created_by);
CREATE POLICY "Criador deleta categoria" ON public.categories  FOR DELETE USING (auth.uid() = created_by);
CREATE POLICY "Delete opções em cascata" ON public.options     FOR DELETE USING (true);

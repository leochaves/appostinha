-- Adiciona coluna slug em tournaments
ALTER TABLE tournaments ADD COLUMN IF NOT EXISTS slug TEXT UNIQUE;

-- Gera slugs para torneios existentes a partir do nome
UPDATE tournaments
SET slug = lower(
  regexp_replace(
    regexp_replace(
      translate(name,
        'àáâãäåèéêëìíîïòóôõöùúûüýÿçñÀÁÂÃÄÅÈÉÊËÌÍÎÏÒÓÔÕÖÙÚÛÜÝÇÑ',
        'aaaaaaeeeeiiiioooooouuuuyyçnaaaaaaeeeeiiiioooooouuuuycn'
      ),
      '[^a-z0-9\s-]', '', 'g'
    ),
    '\s+', '-', 'g'
  )
)
WHERE slug IS NULL;

-- Cria função para garantir slug único ao inserir
CREATE OR REPLACE FUNCTION generate_unique_slug(base_slug TEXT, tournament_id UUID)
RETURNS TEXT AS $$
DECLARE
  candidate TEXT := base_slug;
  counter INT := 1;
BEGIN
  WHILE EXISTS (SELECT 1 FROM tournaments WHERE slug = candidate AND id != tournament_id) LOOP
    candidate := base_slug || '-' || counter;
    counter := counter + 1;
  END LOOP;
  RETURN candidate;
END;
$$ LANGUAGE plpgsql;

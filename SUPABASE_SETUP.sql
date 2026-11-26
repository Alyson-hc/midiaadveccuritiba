-- ============================================================
-- ADVEC Curitiba — Setup/atualização do banco
-- Pode rodar TUDO de novo sem medo (todos os comandos são idempotentes)
-- ============================================================

-- 1) Título do evento/pedido nas solicitações
ALTER TABLE requests ADD COLUMN IF NOT EXISTS title TEXT;

-- 2) Convidados (nome + instagram) nas solicitações
ALTER TABLE requests ADD COLUMN IF NOT EXISTS guests JSONB NOT NULL DEFAULT '[]'::jsonb;

-- 3) Histórico de atividades (quem fez o quê e quando)
ALTER TABLE requests ADD COLUMN IF NOT EXISTS activity JSONB NOT NULL DEFAULT '[]'::jsonb;

-- 3b) Conversa/chat entre departamento e equipe de mídia
ALTER TABLE requests ADD COLUMN IF NOT EXISTS comments JSONB NOT NULL DEFAULT '[]'::jsonb;

-- 4) Senha por departamento (NULL = senha padrão, que é o próprio nome)
ALTER TABLE departments ADD COLUMN IF NOT EXISTS password TEXT;

-- 4b) E-mail do solicitante (recebe confirmações e avisos de status)
ALTER TABLE requests ADD COLUMN IF NOT EXISTS responsible_email TEXT;

-- 4c) Data e hora de término do evento (eventos com mais de 1 dia)
ALTER TABLE requests ADD COLUMN IF NOT EXISTS event_end_date DATE;
ALTER TABLE requests ADD COLUMN IF NOT EXISTS event_end_time TIME;

-- 5) Tabela contents (calendário editorial)
CREATE TABLE IF NOT EXISTS contents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  type TEXT NOT NULL DEFAULT 'post',
  url TEXT,
  description TEXT,
  scheduled_date DATE,
  scheduled_time TIME,
  thumbnail_url TEXT,
  attachments JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE contents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "contents_public_select" ON contents;
DROP POLICY IF EXISTS "contents_public_insert" ON contents;
DROP POLICY IF EXISTS "contents_public_update" ON contents;
DROP POLICY IF EXISTS "contents_public_delete" ON contents;

CREATE POLICY "contents_public_select" ON contents FOR SELECT USING (true);
CREATE POLICY "contents_public_insert" ON contents FOR INSERT WITH CHECK (true);
CREATE POLICY "contents_public_update" ON contents FOR UPDATE USING (true) WITH CHECK (true);
CREATE POLICY "contents_public_delete" ON contents FOR DELETE USING (true);

-- 6) Tabela admins (múltiplos administradores)
CREATE TABLE IF NOT EXISTS admins (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  username TEXT NOT NULL UNIQUE,
  password TEXT NOT NULL,
  email TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- E-mail dos admins (para quem já tinha criado a tabela sem essa coluna)
ALTER TABLE admins ADD COLUMN IF NOT EXISTS email TEXT;

ALTER TABLE admins ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admins_public_select" ON admins;
DROP POLICY IF EXISTS "admins_public_insert" ON admins;
DROP POLICY IF EXISTS "admins_public_update" ON admins;
DROP POLICY IF EXISTS "admins_public_delete" ON admins;

CREATE POLICY "admins_public_select" ON admins FOR SELECT USING (true);
CREATE POLICY "admins_public_insert" ON admins FOR INSERT WITH CHECK (true);
CREATE POLICY "admins_public_update" ON admins FOR UPDATE USING (true) WITH CHECK (true);
CREATE POLICY "admins_public_delete" ON admins FOR DELETE USING (true);

-- Admin geral (mantém a senha atual 1234.9; altere depois em Configurações)
INSERT INTO admins (name, username, password)
VALUES ('Administrador Geral', 'admin', '1234.9')
ON CONFLICT (username) DO NOTHING;

-- 8) Conversa/chat entre departamento e mídia (caso ainda não tenha rodado)
ALTER TABLE requests ADD COLUMN IF NOT EXISTS comments JSONB NOT NULL DEFAULT '[]'::jsonb;

-- 9) Estilos de IA (modelos de referência por departamento, para as abas Criar Arte/Carrossel)
CREATE TABLE IF NOT EXISTS ai_styles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nome TEXT NOT NULL,
  tipo TEXT NOT NULL DEFAULT 'arte',          -- 'arte' ou 'carrossel'
  departamento TEXT,                          -- null = serve para todos
  prompt_base TEXT NOT NULL DEFAULT '',
  refs JSONB NOT NULL DEFAULT '[]'::jsonb,     -- [{ url, path, name }]
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE ai_styles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ai_styles_public_select" ON ai_styles;
DROP POLICY IF EXISTS "ai_styles_public_insert" ON ai_styles;
DROP POLICY IF EXISTS "ai_styles_public_update" ON ai_styles;
DROP POLICY IF EXISTS "ai_styles_public_delete" ON ai_styles;

CREATE POLICY "ai_styles_public_select" ON ai_styles FOR SELECT USING (true);
CREATE POLICY "ai_styles_public_insert" ON ai_styles FOR INSERT WITH CHECK (true);
CREATE POLICY "ai_styles_public_update" ON ai_styles FOR UPDATE USING (true) WITH CHECK (true);
CREATE POLICY "ai_styles_public_delete" ON ai_styles FOR DELETE USING (true);

-- 10) TEMPO REAL — habilita atualização ao vivo em todas as tabelas
--    (isso corrige o bug de precisar recarregar a página!)
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE requests;
EXCEPTION WHEN OTHERS THEN NULL; END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE departments;
EXCEPTION WHEN OTHERS THEN NULL; END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE contents;
EXCEPTION WHEN OTHERS THEN NULL; END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE admins;
EXCEPTION WHEN OTHERS THEN NULL; END $$;

DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE ai_styles;
EXCEPTION WHEN OTHERS THEN NULL; END $$;

-- ============================================================
-- Pronto!
-- ============================================================

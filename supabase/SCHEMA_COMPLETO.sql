-- =====================================================================
-- MINISTÉRIO DE MÍDIA — BANCO COMPLETO (projeto Supabase NOVO)
-- =====================================================================
-- Como usar:
--   supabase.com → seu projeto → SQL Editor → New query →
--   cole ESTE ARQUIVO INTEIRO → Run.
-- Pode rodar de novo sem medo: tudo é "if not exists"/idempotente.
--
-- Depois, copie Project URL + chave "anon public" (Project Settings → API)
-- para o arquivo config.js na raiz do site.
-- =====================================================================

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------------
-- 0) TABELAS BASE (não existiam em nenhum .sql antigo — criadas à mão
--    no projeto original). Colunas tiradas do próprio app.
-- ---------------------------------------------------------------------
create table if not exists public.departments (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  password    text,                        -- null = senha padrão (o próprio nome)
  created_at  timestamptz not null default now()
);

create table if not exists public.requests (
  id                 uuid primary key default gen_random_uuid(),
  department         text,
  department_id      uuid references public.departments(id) on delete set null,
  service_types      text[] not null default '{}',
  title              text,
  responsible_name   text,
  responsible_phone  text,
  responsible_email  text,
  event_date         date,
  event_time         time,
  event_end_date     date,
  event_end_time     time,
  event_location     text,
  guests             jsonb not null default '[]'::jsonb,
  briefing           text,
  reference_files    jsonb not null default '[]'::jsonb,
  status             text not null default 'pendente',
  deliveries         jsonb not null default '[]'::jsonb,
  notes              text default '',
  activity           jsonb not null default '[]'::jsonb,
  comments           jsonb not null default '[]'::jsonb,
  created_at         timestamptz not null default now()
);
create index if not exists requests_created_idx on public.requests (created_at desc);
create index if not exists requests_status_idx  on public.requests (status);

alter table public.departments enable row level security;
alter table public.requests    enable row level security;

drop policy if exists "departments_all" on public.departments;
create policy "departments_all" on public.departments for all using (true) with check (true);
drop policy if exists "requests_all" on public.requests;
create policy "requests_all" on public.requests for all using (true) with check (true);

-- Departamentos padrão
insert into public.departments (name) values
  ('Interligados'), ('Connect'), ('Família'), ('Mulheres'), ('Homens'),
  ('Vencedores Renovados'), ('Start'), ('Interligados Kids')
on conflict (name) do nothing;

-- ---------------------------------------------------------------------
-- 0b) STORAGE — bucket público dos arquivos (até 50 MB por arquivo)
-- ---------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit)
values ('media-files', 'media-files', true, 52428800)
on conflict (id) do update set public = true, file_size_limit = 52428800;

drop policy if exists "media_files_select" on storage.objects;
create policy "media_files_select" on storage.objects for select using (bucket_id = 'media-files');
drop policy if exists "media_files_insert" on storage.objects;
create policy "media_files_insert" on storage.objects for insert with check (bucket_id = 'media-files');
drop policy if exists "media_files_update" on storage.objects;
create policy "media_files_update" on storage.objects for update using (bucket_id = 'media-files') with check (bucket_id = 'media-files');
drop policy if exists "media_files_delete" on storage.objects;
create policy "media_files_delete" on storage.objects for delete using (bucket_id = 'media-files');



-- #####################################################################
-- ### SUPABASE_SETUP.sql
-- #####################################################################

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


-- #####################################################################
-- ### SUPABASE_VOLUNTARIOS.sql
-- #####################################################################

-- =============================================================
-- MÓDULO VOLUNTÁRIOS — Ministério de Mídia (Fase 1)
-- =============================================================
-- Rode este SQL no editor do Supabase (SQL Editor > New query).
-- Cria a tabela de voluntários e libera policies pro app.
-- =============================================================

create extension if not exists "pgcrypto";

create table if not exists public.volunteers (
  id            uuid primary key default gen_random_uuid(),
  name          text not null,
  email         text not null unique,
  phone         text,
  password_hash text not null,
  -- áreas: video | edicao | fotografia | storys | criacao
  areas         text[] not null default '{}',
  -- status: pendente | ativo | inativo | rejeitado
  status        text not null default 'pendente',
  xp            integer not null default 0,
  level         integer not null default 1,
  notes         text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists idx_volunteers_status on public.volunteers(status);
create index if not exists idx_volunteers_email  on public.volunteers(email);

-- Trigger de updated_at
create or replace function public.volunteers_touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_volunteers_touch on public.volunteers;
create trigger trg_volunteers_touch
before update on public.volunteers
for each row execute function public.volunteers_touch_updated_at();

-- RLS — igual ao restante do sistema, aberto (o app já filtra por sessão)
alter table public.volunteers enable row level security;

drop policy if exists volunteers_select on public.volunteers;
drop policy if exists volunteers_insert on public.volunteers;
drop policy if exists volunteers_update on public.volunteers;
drop policy if exists volunteers_delete on public.volunteers;

create policy volunteers_select on public.volunteers for select using (true);
create policy volunteers_insert on public.volunteers for insert with check (true);
create policy volunteers_update on public.volunteers for update using (true) with check (true);
create policy volunteers_delete on public.volunteers for delete using (true);

-- Realtime
alter publication supabase_realtime add table public.volunteers;


-- #####################################################################
-- ### SUPABASE_ESCALAS.sql
-- #####################################################################

-- =============================================================
-- MÓDULO ESCALAS — Ministério de Mídia (Fase 2)
-- =============================================================
-- Rode este SQL DEPOIS de SUPABASE_VOLUNTARIOS.sql.
-- Cria eventos, candidaturas dos voluntários e disponibilidade.
-- =============================================================

create extension if not exists "pgcrypto";

-- 1) EVENTOS DA ESCALA (múltiplos por dia se quiser)
create table if not exists public.events (
  id            uuid primary key default gen_random_uuid(),
  event_date    date not null,
  title         text not null,               -- "Culto da noite", "Ensaio", etc.
  content_idea  text,                        -- ideia geral de conteúdo do dia
  notes         text,
  -- áreas que a escala precisa preencher: video | edicao | fotografia | storys | criacao
  areas_needed  text[] not null default '{}',
  status        text not null default 'aberto',  -- aberto | fechado
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists idx_events_date on public.events(event_date);

create or replace function public.events_touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;
drop trigger if exists trg_events_touch on public.events;
create trigger trg_events_touch before update on public.events
for each row execute function public.events_touch_updated_at();

-- 2) CANDIDATURAS / ESCALADOS
-- Um voluntário se candidata (ou é escalado) para 1 área de 1 evento
create table if not exists public.event_signups (
  id                  uuid primary key default gen_random_uuid(),
  event_id            uuid not null references public.events(id) on delete cascade,
  volunteer_id        uuid not null references public.volunteers(id) on delete cascade,
  area                text not null,                        -- video, edicao, ...
  volunteer_idea      text,                                 -- ideia própria de conteúdo (opcional)
  status              text not null default 'proposto',     -- proposto | confirmado | recusado
  created_at          timestamptz not null default now(),
  unique (event_id, volunteer_id, area)
);

create index if not exists idx_signups_event on public.event_signups(event_id);
create index if not exists idx_signups_vol   on public.event_signups(volunteer_id);

-- 3) DISPONIBILIDADE — voluntário marca dias em que está disponível
create table if not exists public.availability (
  volunteer_id  uuid not null references public.volunteers(id) on delete cascade,
  day           date not null,
  created_at    timestamptz not null default now(),
  primary key (volunteer_id, day)
);

-- RLS aberto (o app já filtra por sessão)
alter table public.events         enable row level security;
alter table public.event_signups  enable row level security;
alter table public.availability   enable row level security;

drop policy if exists events_all         on public.events;
drop policy if exists signups_all        on public.event_signups;
drop policy if exists availability_all   on public.availability;

create policy events_all       on public.events        for all using (true) with check (true);
create policy signups_all      on public.event_signups for all using (true) with check (true);
create policy availability_all on public.availability  for all using (true) with check (true);

-- Realtime
alter publication supabase_realtime add table public.events;
alter publication supabase_realtime add table public.event_signups;
alter publication supabase_realtime add table public.availability;


-- #####################################################################
-- ### SUPABASE_FEEDBACKS.sql
-- #####################################################################

-- =============================================================
-- MÓDULO FEEDBACKS + GAMIFICAÇÃO — Fase 3
-- =============================================================
-- Rode DEPOIS de SUPABASE_VOLUNTARIOS.sql e SUPABASE_ESCALAS.sql.
-- =============================================================

create extension if not exists "pgcrypto";

create table if not exists public.feedbacks (
  id            uuid primary key default gen_random_uuid(),
  volunteer_id  uuid not null references public.volunteers(id) on delete cascade,
  event_id      uuid references public.events(id) on delete set null,
  area          text,                              -- video, edicao, fotografia, storys, criacao
  rating        smallint not null check (rating between 1 and 5),
  note          text,
  author        text,                              -- nome do admin
  created_at    timestamptz not null default now()
);

create index if not exists idx_fb_vol   on public.feedbacks(volunteer_id);
create index if not exists idx_fb_event on public.feedbacks(event_id);

alter table public.feedbacks enable row level security;
drop policy if exists feedbacks_all on public.feedbacks;
create policy feedbacks_all on public.feedbacks for all using (true) with check (true);

-- Trigger: XP automático ao receber feedback (rating * 20 XP)
create or replace function public.feedback_award_xp()
returns trigger language plpgsql as $$
begin
  update public.volunteers
    set xp = coalesce(xp, 0) + (new.rating * 20)
  where id = new.volunteer_id;
  return new;
end;
$$;
drop trigger if exists trg_feedback_xp on public.feedbacks;
create trigger trg_feedback_xp after insert on public.feedbacks
for each row execute function public.feedback_award_xp();

-- Trigger: XP quando signup vira 'confirmado' (+50 XP, só uma vez por signup)
create or replace function public.signup_award_xp()
returns trigger language plpgsql as $$
begin
  if new.status = 'confirmado' and (old.status is null or old.status <> 'confirmado') then
    update public.volunteers
      set xp = coalesce(xp, 0) + 50
    where id = new.volunteer_id;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_signup_xp on public.event_signups;
create trigger trg_signup_xp after update on public.event_signups
for each row execute function public.signup_award_xp();

-- Realtime
alter publication supabase_realtime add table public.feedbacks;


-- #####################################################################
-- ### SUPABASE_FASE4.sql
-- #####################################################################

-- =============================================================
-- FASE 4 — Nota 0-10, mural de avisos, XP só por avaliação
-- =============================================================
-- Rode DEPOIS de VOLUNTARIOS, ESCALAS e FEEDBACKS.
-- =============================================================

-- 1) XP passa a subir SÓ quando adm dá nota (não por confirmação de escala)
drop trigger if exists trg_signup_xp on public.event_signups;

-- 2) Feedback: rating agora vai de 0 a 10, e cada ponto vale 10 XP
alter table public.feedbacks drop constraint if exists feedbacks_rating_check;
alter table public.feedbacks add constraint feedbacks_rating_check check (rating between 0 and 10);

create or replace function public.feedback_award_xp()
returns trigger language plpgsql as $$
begin
  update public.volunteers
    set xp = coalesce(xp, 0) + (new.rating * 10)
  where id = new.volunteer_id;
  return new;
end;
$$;

-- 3) Mural de avisos (admin manda, voluntário vê no topo)
create table if not exists public.announcements (
  id           uuid primary key default gen_random_uuid(),
  message      text not null,
  areas        text[] not null default '{}',  -- se vazio, aparece pra todos
  pinned       boolean not null default true,
  author       text,
  created_at   timestamptz not null default now()
);

alter table public.announcements enable row level security;
drop policy if exists announcements_all on public.announcements;
create policy announcements_all on public.announcements for all using (true) with check (true);

alter publication supabase_realtime add table public.announcements;


-- #####################################################################
-- ### SUPABASE_FASE5.sql
-- #####################################################################

-- =============================================================
-- FASE 5 — Autoserviço de áreas + graus de admin
-- =============================================================

-- 1) Voluntário pode solicitar novas áreas (admin aprova)
create table if not exists public.volunteer_area_requests (
  id            uuid primary key default gen_random_uuid(),
  volunteer_id  uuid not null references public.volunteers(id) on delete cascade,
  area          text not null,   -- video, edicao, fotografia, storys, criacao
  status        text not null default 'pendente',   -- pendente | aprovado | rejeitado
  reason        text,
  created_at    timestamptz not null default now(),
  reviewed_at   timestamptz,
  reviewed_by   text,
  unique (volunteer_id, area, status)
);

create index if not exists idx_area_req_vol on public.volunteer_area_requests(volunteer_id);
create index if not exists idx_area_req_status on public.volunteer_area_requests(status);

alter table public.volunteer_area_requests enable row level security;
drop policy if exists area_req_all on public.volunteer_area_requests;
create policy area_req_all on public.volunteer_area_requests for all using (true) with check (true);
-- idempotente: se a tabela ja estiver no realtime, o "add table" puro dava erro
-- e o Supabase desfazia o script inteiro (inclusive as colunas de admin abaixo)
do $$ begin
  alter publication supabase_realtime add table public.volunteer_area_requests;
exception when duplicate_object then null;
end $$;

-- 2) Graus de admin: role + áreas gerenciadas
alter table public.admins add column if not exists role  text not null default 'super_admin';   -- super_admin | coordinator
alter table public.admins add column if not exists areas text[] not null default '{}';           -- só usado por coordinator

-- 3) PostgREST enxerga as colunas novas na hora (sem isso: "schema cache")
notify pgrst, 'reload schema';


-- #####################################################################
-- ### SUPABASE_FASE6_WHATSAPP.sql
-- #####################################################################

-- =============================================================
-- FASE 6 — Notificações WhatsApp (via Evolution API)
-- =============================================================
-- Rode DEPOIS das fases anteriores.
-- =============================================================

-- 1) Voluntário guarda o número de WhatsApp (whatsapp_key não é mais usado c/ Evolution)
alter table public.volunteers add column if not exists whatsapp      text;
alter table public.volunteers add column if not exists whatsapp_key  text;
alter table public.volunteers add column if not exists notify        boolean not null default true;

-- 2) Log das mensagens enviadas — evita repetir a mesma msg pro mesmo alvo
create table if not exists public.whatsapp_log (
  id            uuid primary key default gen_random_uuid(),
  volunteer_id  uuid not null references public.volunteers(id) on delete cascade,
  kind          text not null,         -- new_event | confirmed | day_reminder | custom
  reference     text,                  -- event_id ou signup_id ou 'YYYY-MM-DD' para o lembrete diário
  message       text,
  ok            boolean not null default true,
  error         text,
  created_at    timestamptz not null default now(),
  unique (volunteer_id, kind, reference)
);

create index if not exists idx_wlog_ref on public.whatsapp_log(kind, reference);

alter table public.whatsapp_log enable row level security;
drop policy if exists wlog_all on public.whatsapp_log;
create policy wlog_all on public.whatsapp_log for all using (true) with check (true);
alter publication supabase_realtime add table public.whatsapp_log;


-- #####################################################################
-- ### SUPABASE_FASE8_TREINAMENTO.sql
-- #####################################################################

-- =============================================================
-- FASE 8 — Treinamento + Nota mínima nas escalas
-- =============================================================
-- Rode 1x no SQL Editor do Supabase.
--
-- Regras:
--  * volunteer.training_stage:
--      0 = novo (nunca fez treinamento)
--      1 = conheceu e acompanhou
--      2 = praticou com alguém ao lado
--      3 = praticou sozinho (com supervisão)
--      4 = aprovado (formado)
--  * Escalas não-treinamento aparecem só para quem tem stage >= 3
--  * Cada evento pode ter min_rating (nota mínima 0-10) — quem tem
--    média abaixo não vê a escala
--  * Eventos is_training=true têm training_stage (1..4) marcando a
--    etapa que aquele treino cobre — só quem está exatamente na etapa
--    anterior enxerga
-- =============================================================

alter table public.volunteers
  add column if not exists training_stage int not null default 0
  check (training_stage between 0 and 4);

alter table public.events
  add column if not exists is_training boolean not null default false;

alter table public.events
  add column if not exists training_stage int
  check (training_stage is null or training_stage between 1 and 4);

alter table public.events
  add column if not exists min_rating numeric(3,1) not null default 0
  check (min_rating between 0 and 10);

notify pgrst, 'reload schema';


-- #####################################################################
-- ### SUPABASE_FASE9_ESTUDO_FORUM.sql
-- #####################################################################

-- =============================================================
-- ATUALIZAÇÃO DO SISTEMA — Ministério de Mídia (ADVEC Curitiba)
-- Estudo + Fórum + Recado por área + FUNÇÕES DE CULTO
-- =============================================================
-- Cole TUDO isto no Supabase → SQL Editor → New query → Run.
-- É seguro rodar mais de uma vez (tudo usa "if not exists").
-- Não apaga nem altera nenhum dado existente.
-- =============================================================

create extension if not exists "pgcrypto";

-- -------------------------------------------------------------
-- 1) RECADO POR ÁREA NA ESCALA
--    Cada evento guarda um recado por área: {"video":"...","edicao":"..."}
-- -------------------------------------------------------------
alter table public.events
  add column if not exists area_notes jsonb not null default '{}'::jsonb;

-- -------------------------------------------------------------
-- 1b) FUNÇÕES DE CULTO (telão, corte, transmissão, letra, câmeras, grua)
--     - events.roles_needed      : quais postos essa escala precisa preencher
--     - event_signups.role       : qual posto a pessoa ocupa nessa escala
--     - volunteers.qualified_roles: em quais funções a pessoa está HABILITADA
--                                   (passou pelo treinamento daquela função)
-- -------------------------------------------------------------
alter table public.events
  add column if not exists roles_needed text[] not null default '{}';

alter table public.event_signups
  add column if not exists role text;

alter table public.volunteers
  add column if not exists qualified_roles text[] not null default '{}';

create index if not exists idx_signups_role on public.event_signups(role);

-- -------------------------------------------------------------
-- 2) ÁREA DE ESTUDO
--    Vídeos / links / textos que a liderança posta pros voluntários.
--    areas vazio = aparece pra todos os voluntários.
-- -------------------------------------------------------------
create table if not exists public.study_materials (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  description  text,
  url          text,
  kind         text not null default 'link',    -- video | link | texto
  areas        text[] not null default '{}',     -- video | edicao | fotografia | storys | criacao
  author       text,
  created_at   timestamptz not null default now()
);
create index if not exists idx_study_created on public.study_materials(created_at desc);

alter table public.study_materials enable row level security;
drop policy if exists study_all on public.study_materials;
create policy study_all on public.study_materials for all using (true) with check (true);

-- -------------------------------------------------------------
-- 3) FÓRUM DAS ÁREAS
--    parent_id null  = pergunta (thread)
--    parent_id preenchido = resposta daquela pergunta
--    author_type: volunteer | admin
-- -------------------------------------------------------------
create table if not exists public.forum_posts (
  id           uuid primary key default gen_random_uuid(),
  area         text,                              -- video | edicao | fotografia | storys | criacao
  parent_id    uuid references public.forum_posts(id) on delete cascade,
  author_type  text not null default 'volunteer',
  author_id    text,                              -- text (aceita id de admin/voluntário ou vazio)
  author_name  text,
  body         text not null,
  created_at   timestamptz not null default now()
);
create index if not exists idx_forum_area   on public.forum_posts(area);
create index if not exists idx_forum_parent on public.forum_posts(parent_id);
create index if not exists idx_forum_created on public.forum_posts(created_at);

alter table public.forum_posts enable row level security;
drop policy if exists forum_all on public.forum_posts;
create policy forum_all on public.forum_posts for all using (true) with check (true);

-- =============================================================
-- Pronto! Volte no site e dê um Ctrl+Shift+R (ou ⌘+Shift+R).
-- Passam a funcionar: abas "Estudo" e "Fórum", recado por área,
-- e as FUNÇÕES DE CULTO (montar escala + enviar no WhatsApp).
--
-- Próximo passo no sistema:
--   1) Voluntários → editar cada pessoa → marque as "Funções habilitadas"
--   2) Escalas → criar/editar evento → escolha as "Funções do culto"
--   3) Clique no evento → monte a escala → "Enviar escala no WhatsApp"
-- =============================================================


-- #####################################################################
-- ### FIX_ANNOUNCEMENTS.sql
-- #####################################################################

-- =============================================================
-- FIX — Criar tabela de anúncios do mural
-- =============================================================
-- Erro: "Could not find the table 'public.announcements' in the schema cache"
-- Rode isso no SQL editor do Supabase e o mural passa a funcionar.
-- =============================================================

create table if not exists public.announcements (
  id           uuid primary key default gen_random_uuid(),
  message      text not null,
  areas        text[] not null default '{}',  -- se vazio, aparece pra todos
  pinned       boolean not null default true,
  author       text,
  created_at   timestamptz not null default now()
);

alter table public.announcements enable row level security;
drop policy if exists announcements_all on public.announcements;
create policy announcements_all on public.announcements for all using (true) with check (true);

-- Adiciona ao realtime (ignora erro se já estiver)
do $$
begin
  begin
    alter publication supabase_realtime add table public.announcements;
  exception when duplicate_object then null;
  end;
end $$;

-- Força refresh do schema cache do PostgREST
notify pgrst, 'reload schema';


-- #####################################################################
-- ### FIX_FEEDBACK_RATING.sql
-- #####################################################################

-- Corrige o CHECK do rating para aceitar 0-10 (Fase 4)
alter table public.feedbacks drop constraint if exists feedbacks_rating_check;
alter table public.feedbacks add constraint feedbacks_rating_check check (rating between 0 and 10);


-- #####################################################################
-- ### FIX_BACKFILL_WHATSAPP.sql
-- #####################################################################

-- =============================================================
-- FIX — Copia phone → whatsapp em voluntários sem whatsapp
-- =============================================================
-- Voluntários se cadastraram só com 'phone', mas o mural manda
-- WhatsApp usando o campo 'whatsapp'. Esse SQL copia um pro outro.
--
-- Rode 1x no SQL Editor do Supabase.
-- =============================================================

-- 1) Se o campo whatsapp está nulo ou vazio, copia o phone
update public.volunteers
set whatsapp = phone
where (whatsapp is null or whatsapp = '')
  and phone is not null
  and phone <> '';

-- 2) Garante notify = true onde estiver nulo (defensivo)
update public.volunteers
set notify = true
where notify is null;

-- 3) Diagnóstico — mostra quantos ficaram com WhatsApp funcionando
select
  count(*) as total,
  count(*) filter (where status = 'ativo') as ativos,
  count(*) filter (where status = 'ativo' and (whatsapp is not null and whatsapp <> '')) as ativos_com_whatsapp,
  count(*) filter (where status = 'ativo' and (whatsapp is null or whatsapp = '') and (phone is null or phone = '')) as ativos_sem_nenhum_fone,
  count(*) filter (where status = 'ativo' and notify = true) as ativos_com_notify_on
from public.volunteers;


-- #####################################################################
-- ### SUPABASE_AGENDA_CONTEUDO.sql
-- #####################################################################

-- =============================================================
-- AGENDA DE CONTEÚDO — categorias coloridas + itens por dia
-- =============================================================
-- Seguro rodar mais de uma vez. Já incluído no SCHEMA_COMPLETO.sql.
-- =============================================================

create extension if not exists "pgcrypto";

-- Categorias (cada uma com sua cor). O admin cria/edita no app.
create table if not exists public.agenda_categories (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  color       text not null default '#2B77E4',   -- hex
  position    int  not null default 0,
  created_at  timestamptz not null default now()
);

-- Itens da agenda
create table if not exists public.agenda_items (
  id           uuid primary key default gen_random_uuid(),
  category_id  uuid references public.agenda_categories(id) on delete set null,
  title        text not null,
  item_date    date not null,
  start_time   time,
  end_time     time,
  description  text,
  links        jsonb not null default '[]'::jsonb,   -- [{ label, url }]
  files        jsonb not null default '[]'::jsonb,   -- [{ id, path, url, name, size, type }]
  created_by   text,
  created_at   timestamptz not null default now()
);
create index if not exists agenda_items_date_idx on public.agenda_items (item_date);

alter table public.agenda_categories enable row level security;
alter table public.agenda_items      enable row level security;
drop policy if exists "agenda_categories_all" on public.agenda_categories;
create policy "agenda_categories_all" on public.agenda_categories for all using (true) with check (true);
drop policy if exists "agenda_items_all" on public.agenda_items;
create policy "agenda_items_all" on public.agenda_items for all using (true) with check (true);

-- Tempo real
do $$ begin alter publication supabase_realtime add table public.agenda_categories; exception when others then null; end $$;
do $$ begin alter publication supabase_realtime add table public.agenda_items;      exception when others then null; end $$;

-- Categorias iniciais (edite/apague à vontade no app)
insert into public.agenda_categories (name, color, position) values
  ('Vídeo gravado',              '#2B77E4', 1),
  ('Live',                       '#EF4444', 2),
  ('Gravação de conteúdo',       '#C1ED28', 3),
  ('Ideia de conteúdo p/ culto', '#A855F7', 4),
  ('Post / Arte',                '#F59E0B', 5),
  ('Fotografia',                 '#06B6D4', 6)
on conflict (name) do nothing;


-- #####################################################################
-- ### SUPABASE_FASE10_VOLUNTARIOS_AGENDA.sql
-- #####################################################################

-- =============================================================
-- FASE 10 — Agenda: tipo "post" + responsáveis | Voluntários:
--           troca de escala + envio de material pós-culto
-- =============================================================
-- Cole no Supabase → SQL Editor → New query → Run.
-- Seguro rodar mais de uma vez. Não apaga nada.
-- =============================================================

create extension if not exists "pgcrypto";

-- 1) AGENDA: categoria pode ser "evento" (início e fim) ou "post" (um horário)
alter table public.agenda_categories add column if not exists kind text not null default 'evento';

-- 2) AGENDA: responsáveis/coordenadores marcados no item  [{ id, name, kind }]
alter table public.agenda_items add column if not exists people jsonb not null default '[]'::jsonb;

-- Categoria "Post" (um horário só)
insert into public.agenda_categories (name, color, position, kind)
values ('Post', '#EC4899', 0, 'post')
on conflict (name) do update set kind = 'post';
update public.agenda_categories set kind = 'post' where name = 'Post / Arte';

-- 3) TROCA DE ESCALA — voluntário oferece a vaga; colega da área assume
create table if not exists public.scale_swaps (
  id                 uuid primary key default gen_random_uuid(),
  signup_id          uuid not null references public.event_signups(id) on delete cascade,
  event_id           uuid references public.events(id) on delete cascade,
  area               text,
  role               text,
  from_volunteer_id  uuid references public.volunteers(id) on delete cascade,
  to_volunteer_id    uuid references public.volunteers(id) on delete set null,
  reason             text,
  status             text not null default 'aberta',   -- aberta | assumida | cancelada
  created_at         timestamptz not null default now(),
  taken_at           timestamptz
);
create index if not exists scale_swaps_status_idx on public.scale_swaps (status);

-- 4) MATERIAL DO CULTO — fotos/vídeos enviados pelo voluntário depois de servir
create table if not exists public.event_uploads (
  id            uuid primary key default gen_random_uuid(),
  event_id      uuid references public.events(id) on delete set null,
  volunteer_id  uuid references public.volunteers(id) on delete set null,
  area          text,
  note          text,
  files         jsonb not null default '[]'::jsonb,
  created_at    timestamptz not null default now()
);
create index if not exists event_uploads_event_idx on public.event_uploads (event_id);

alter table public.scale_swaps   enable row level security;
alter table public.event_uploads enable row level security;
drop policy if exists "scale_swaps_all" on public.scale_swaps;
create policy "scale_swaps_all" on public.scale_swaps for all using (true) with check (true);
drop policy if exists "event_uploads_all" on public.event_uploads;
create policy "event_uploads_all" on public.event_uploads for all using (true) with check (true);

do $$ begin alter publication supabase_realtime add table public.scale_swaps;   exception when others then null; end $$;
do $$ begin alter publication supabase_realtime add table public.event_uploads; exception when others then null; end $$;


-- Pronto! Agora preencha config.js com a URL e a chave anon.

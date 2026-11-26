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

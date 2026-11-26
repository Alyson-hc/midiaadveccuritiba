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

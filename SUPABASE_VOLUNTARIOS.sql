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

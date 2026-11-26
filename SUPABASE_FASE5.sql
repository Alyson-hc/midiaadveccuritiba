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

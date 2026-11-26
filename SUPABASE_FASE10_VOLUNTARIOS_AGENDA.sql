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

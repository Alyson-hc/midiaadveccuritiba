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

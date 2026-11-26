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

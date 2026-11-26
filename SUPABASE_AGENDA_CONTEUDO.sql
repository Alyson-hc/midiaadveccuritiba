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

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

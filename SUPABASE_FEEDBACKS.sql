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

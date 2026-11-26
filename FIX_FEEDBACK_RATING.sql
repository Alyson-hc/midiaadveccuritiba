-- Corrige o CHECK do rating para aceitar 0-10 (Fase 4)
alter table public.feedbacks drop constraint if exists feedbacks_rating_check;
alter table public.feedbacks add constraint feedbacks_rating_check check (rating between 0 and 10);

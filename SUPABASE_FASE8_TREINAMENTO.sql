-- =============================================================
-- FASE 8 — Treinamento + Nota mínima nas escalas
-- =============================================================
-- Rode 1x no SQL Editor do Supabase.
--
-- Regras:
--  * volunteer.training_stage:
--      0 = novo (nunca fez treinamento)
--      1 = conheceu e acompanhou
--      2 = praticou com alguém ao lado
--      3 = praticou sozinho (com supervisão)
--      4 = aprovado (formado)
--  * Escalas não-treinamento aparecem só para quem tem stage >= 3
--  * Cada evento pode ter min_rating (nota mínima 0-10) — quem tem
--    média abaixo não vê a escala
--  * Eventos is_training=true têm training_stage (1..4) marcando a
--    etapa que aquele treino cobre — só quem está exatamente na etapa
--    anterior enxerga
-- =============================================================

alter table public.volunteers
  add column if not exists training_stage int not null default 0
  check (training_stage between 0 and 4);

alter table public.events
  add column if not exists is_training boolean not null default false;

alter table public.events
  add column if not exists training_stage int
  check (training_stage is null or training_stage between 1 and 4);

alter table public.events
  add column if not exists min_rating numeric(3,1) not null default 0
  check (min_rating between 0 and 10);

notify pgrst, 'reload schema';

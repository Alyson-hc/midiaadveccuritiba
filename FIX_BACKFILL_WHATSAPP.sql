-- =============================================================
-- FIX — Copia phone → whatsapp em voluntários sem whatsapp
-- =============================================================
-- Voluntários se cadastraram só com 'phone', mas o mural manda
-- WhatsApp usando o campo 'whatsapp'. Esse SQL copia um pro outro.
--
-- Rode 1x no SQL Editor do Supabase.
-- =============================================================

-- 1) Se o campo whatsapp está nulo ou vazio, copia o phone
update public.volunteers
set whatsapp = phone
where (whatsapp is null or whatsapp = '')
  and phone is not null
  and phone <> '';

-- 2) Garante notify = true onde estiver nulo (defensivo)
update public.volunteers
set notify = true
where notify is null;

-- 3) Diagnóstico — mostra quantos ficaram com WhatsApp funcionando
select
  count(*) as total,
  count(*) filter (where status = 'ativo') as ativos,
  count(*) filter (where status = 'ativo' and (whatsapp is not null and whatsapp <> '')) as ativos_com_whatsapp,
  count(*) filter (where status = 'ativo' and (whatsapp is null or whatsapp = '') and (phone is null or phone = '')) as ativos_sem_nenhum_fone,
  count(*) filter (where status = 'ativo' and notify = true) as ativos_com_notify_on
from public.volunteers;

# ADVEC Curitiba · Ministério de Mídia

Plataforma interna de gerenciamento de solicitações de mídia da ADVEC Curitiba.

## Stack

- **HTML único** com React + Tailwind via CDN (sem build)
- **Supabase** — banco de dados, storage de arquivos e sincronização em tempo real
- **Hospedagem estática** — Vercel / Netlify / GitHub Pages

## Como funciona

1. Cada departamento entra digitando o nome no login
2. O admin entra digitando `admin` e a senha `1234.9`
3. Tudo é salvo no Supabase e sincroniza em tempo real entre todos os dispositivos
4. Upload de arquivos até 50MB

## Setup do Supabase

O projeto Supabase já está configurado em `https://snptddlodvfaskjerliq.supabase.co`.

Tabelas necessárias:
- `departments` (id, name, created_at)
- `requests` (id, department, department_id, service_types[], responsible_name,
  responsible_phone, event_date, event_time, event_location, briefing,
  reference_files (jsonb), status, deliveries (jsonb), notes, created_at)

Storage bucket: `media-files` (público)

## Deploy

Como é um único arquivo HTML, basta hospedar como site estático:

- **Vercel**: conecta o repositório, deploy automático em cada push
- **Netlify**: arrasta o `index.html` em <https://app.netlify.com/drop>
- **GitHub Pages**: Settings → Pages → enable

## Credenciais

- Senha admin: `1234.9`
- Cada departamento tem senha própria. **Senha padrão = o próprio nome do departamento**
  (ignora acentos/maiúsculas). O departamento altera em *Configurações*; o admin vê e
  altera qualquer senha em *Departamentos → editar*.
- Departamentos padrão: Interligados, Connect, Família, Mulheres, Homens, Vencedores Renovados, Start, Interligados Kids

# ADVEC Curitiba · Ministério de Mídia

Plataforma interna de gerenciamento de solicitações de mídia da ADVEC Curitiba.

## Stack

- HTML único: React + Tailwind via CDN
- Supabase: banco, storage, realtime
- Hospedagem estática (Netlify), com um passo de build que compila o JSX

## Build

**Edite sempre `src/index.html`** — é o arquivo-fonte, com JSX solto.

O `index.html` da **raiz é gerado** por `npm run build` e vai commitado: a
Hostinger publica a raiz do repositório direto do GitHub, sem rodar build.
Compilar antes tira do navegador de cada visitante o Babel (584 KB comprimidos)
e a compilação de ~570 KB de JSX a cada carregamento.

```
npm install
npm run build          # index.html da raiz, minificado
npm run build:debug    # index.html da raiz legível, pra depurar
```

Esqueceu de rodar o build antes do push? A Action `.github/workflows/build.yml`
compila e commita o `index.html` sozinha quando `src/` muda.

Testar local sem build: `python3 -m http.server 5173` e abra
<http://localhost:5173/src/index.html> (compila no navegador, como antes).

## Como funciona

1. Departamento entra digitando nome no login
2. Admin entra com `admin` e senha `1234.9`
3. Tudo salva no Supabase, sincroniza em tempo real
4. Upload até 50MB

## Banco de dados (Supabase)

A conexão fica em **`config.js`** (raiz do site), não no código. Trocar de
banco = editar esse arquivo, sem build. Sem config válida, o site mostra uma
tela explicando como conectar; se o banco não responder, aparece um aviso.

> O projeto antigo (`snptddlodvfaskjerliq.supabase.co`) não existe mais
> (o endereço não resolve). É preciso criar um novo.

Projeto novo, uma vez só:

1. supabase.com → New project.
2. SQL Editor → New query → cole **`supabase/SCHEMA_COMPLETO.sql`** inteiro → Run.
   Cria todas as tabelas, o bucket `media-files`, as policies, o tempo real,
   os departamentos padrão e o admin (`admin` / `1234.9`, troque depois).
3. Project Settings → API → copie *Project URL* e a chave *anon public* para `config.js`.
4. Atualização mais recente: rode também `SUPABASE_FASE10_VOLUNTARIOS_AGENDA.sql` (posts e responsáveis na agenda, troca de escala, material pós-culto). Já está dentro do SCHEMA_COMPLETO para projetos novos.
5. (Opcional) Funções de IA e WhatsApp: publique `supabase/functions/*` no
   projeto novo (`supabase functions deploy gerar-arte send-evolution evolution-status`).

Os `SUPABASE_*.sql` / `FIX_*.sql` antigos ficam só como histórico: o
`SCHEMA_COMPLETO.sql` já junta todos, na ordem certa.

## Identidade visual (GVV)

- Cores: azul `#2B77E4` (acento), verde-limão `#C1ED28` (destaque),
  off-white `#F9F4EB` (tema claro), preto `#000` (tema escuro, com brilho turquesa).
- Fontes: Arlen (títulos) e Helvetica Now Display (texto). Como são pagas, o site
  usa Anton e Inter Tight (Google Fonts) no lugar; se as originais estiverem
  instaladas no computador, entram automaticamente.
- Tokens em `GlobalStyles` (`--brand`, `--gvv-*`, `--z-*`): mudar ali muda o app todo.

## Deploy

Hostinger, conectada ao repositório (`midiaadvec.site`): cada push na `main`
publica a raiz. O `.htaccess` tira o cache do HTML e bloqueia `src/`, `.sql`
e demais arquivos de desenvolvimento.

## Credenciais

- Senha admin: `1234.9`
- Cada departamento tem senha própria. Padrão = nome do departamento
  (ignora acentos/maiúsculas). Departamento altera em *Configurações*; admin altera
  qualquer senha em *Departamentos → editar*.
- Departamentos padrão: Interligados, Connect, Família, Mulheres, Homens, Vencedores Renovados, Start, Interligados Kids

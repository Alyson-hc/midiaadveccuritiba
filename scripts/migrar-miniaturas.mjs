/**
 * Tira as miniaturas base64 de dentro da tabela `requests` e sobe cada uma
 * como arquivo no Storage (bucket media-files), trocando o texto pela URL.
 *
 * Por que: 41 pedidos ocupavam 2,1 MB so por causa dessas miniaturas, e o app
 * baixa essa tabela inteira ao abrir.
 *
 *   node scripts/migrar-miniaturas.mjs            -> simulacao (nao grava nada)
 *   node scripts/migrar-miniaturas.mjs --aplicar  -> grava
 *
 * Antes de gravar salva um backup completo em backups/ (fora do git).
 * Cada pedido e relido logo antes de ser atualizado, e so as colunas
 * reference_files e deliveries sao enviadas.
 */
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';

const APPLY = process.argv.includes('--aplicar');
const html = await readFile(new URL('../src/index.html', import.meta.url), 'utf8');
const URL_BASE = html.match(/const SUPABASE_URL = "([^"]+)"/)[1];
const KEY = html.match(/const SUPABASE_ANON_KEY = "([^"]+)"/)[1];
const BUCKET = 'media-files';
const H = { apikey: KEY, Authorization: `Bearer ${KEY}` };

const api = async (path, opts = {}) => {
  const r = await fetch(`${URL_BASE}${path}`, { ...opts, headers: { ...H, ...(opts.headers || {}) } });
  if (!r.ok) throw new Error(`${opts.method || 'GET'} ${path.split('?')[0]} -> ${r.status} ${await r.text()}`);
  return r.status === 204 ? null : r.json();
};

const isData = (t) => typeof t === 'string' && t.startsWith('data:');

const uploadThumb = async (dataUrl) => {
  const m = /^data:([^;,]+)?(;base64)?,(.*)$/s.exec(dataUrl);
  if (!m) throw new Error('data URL invalida');
  const type = m[1] || 'image/jpeg';
  const bytes = m[2] ? Buffer.from(m[3], 'base64') : Buffer.from(decodeURIComponent(m[3]));
  const ext = type.includes('png') ? 'png' : 'jpg';
  const path = `thumb-${randomUUID()}.${ext}`;
  const r = await fetch(`${URL_BASE}/storage/v1/object/${BUCKET}/${path}`, {
    method: 'POST',
    headers: { ...H, 'Content-Type': type, 'x-upsert': 'false', 'cache-control': 'max-age=31536000' },
    body: bytes,
  });
  if (!r.ok) throw new Error(`upload ${r.status} ${await r.text()}`);
  return { url: `${URL_BASE}/storage/v1/object/public/${BUCKET}/${path}`, path };
};

// devolve copia com as miniaturas trocadas (ou so conta, na simulacao)
const convert = async (row, stats) => {
  const fix = async (f) => {
    if (!f || !isData(f.thumbnail)) return f;
    stats.thumbs++;
    stats.bytes += f.thumbnail.length;
    if (!APPLY) return f;
    const t = await uploadThumb(f.thumbnail);
    return { ...f, thumbnail: t.url, thumbPath: t.path };
  };
  const reference_files = await Promise.all((row.reference_files || []).map(fix));
  const deliveries = await Promise.all((row.deliveries || []).map(async (d) =>
    d?.file ? { ...d, file: await fix(d.file) } : d));
  return { reference_files, deliveries };
};

const all = await api('/rest/v1/requests?select=*');
const before = JSON.stringify(all).length;
const targets = all.filter(r =>
  (r.reference_files || []).some(f => isData(f?.thumbnail)) ||
  (r.deliveries || []).some(d => isData(d?.file?.thumbnail)));

console.log(`${all.length} pedidos, ${(before / 1024).toFixed(0)} KB no total`);
console.log(`${targets.length} pedidos com miniatura dentro do banco`);

if (APPLY) {
  await mkdir(new URL('../backups/', import.meta.url), { recursive: true });
  const file = new URL(`../backups/requests-${new Date().toISOString().replace(/[:.]/g, '-')}.json`, import.meta.url);
  await writeFile(file, JSON.stringify(all));
  console.log(`backup: ${file.pathname}`);
}

const stats = { thumbs: 0, bytes: 0, done: 0, failed: 0 };
for (const t of targets) {
  try {
    // rele a linha na hora: alguem pode ter mexido desde a leitura acima
    const [fresh] = await api(`/rest/v1/requests?id=eq.${t.id}&select=id,reference_files,deliveries`);
    if (!fresh) continue;
    const patch = await convert(fresh, stats);
    if (APPLY) {
      await api(`/rest/v1/requests?id=eq.${t.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json', Prefer: 'return=minimal' },
        body: JSON.stringify(patch),
      });
    }
    stats.done++;
  } catch (e) {
    stats.failed++;
    console.error(`pedido ${t.id}: ${e.message}`);
  }
}

console.log(`${stats.thumbs} miniaturas (${(stats.bytes / 1024).toFixed(0)} KB) em ${stats.done} pedidos${stats.failed ? `, ${stats.failed} com erro` : ''}`);
if (APPLY) {
  const after = JSON.stringify(await api('/rest/v1/requests?select=*')).length;
  console.log(`tabela: ${(before / 1024).toFixed(0)} KB -> ${(after / 1024).toFixed(0)} KB`);
} else {
  console.log('simulacao — nada foi gravado. Rode com --aplicar para gravar.');
}

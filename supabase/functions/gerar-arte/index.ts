// Porteiro seguro da IA — roda na Supabase Edge (Deno).
// A chave NUNCA vai pro navegador.
//
// Suporta 3 provedores; escolha pela env AI_PROVIDER:
//   AI_PROVIDER = freepik | gemini | openai
//
// Env vars (Supabase → Project Settings → Edge Functions → Secrets):
//   AI_PROVIDER, FREEPIK_API_KEY, FREEPIK_MODEL, FREEPIK_IMAGE_SIZE,
//   GEMINI_API_KEY, GEMINI_MODEL,
//   OPENAI_API_KEY, OPENAI_MODEL

import { cors } from '../_shared/cors.ts';

const DEFAULT_PROVIDER = 'freepik';
const DEFAULT_FREEPIK_MODEL = 'gemini-2-5-flash-image-preview';
const DEFAULT_GEMINI_MODEL = 'gemini-3-pro-image-preview';
const DEFAULT_OPENAI_MODEL = 'gpt-image-1.5';
const MAX_IMAGES = 4;

const REF_IMAGE_MODELS = ['gemini-2-5-flash-image-preview', 'gpt-image-2'];
const INPUT_IMAGE_MODELS = ['flux-kontext-pro'];

const jsonHeaders = { ...cors, 'Content-Type': 'application/json' };
const reply = (status: number, obj: unknown) =>
  new Response(JSON.stringify(obj), { status, headers: jsonHeaders });

function withStatus(message: string, status: number, detail?: unknown) {
  const e = new Error(message) as Error & { status?: number; detail?: unknown };
  e.status = status;
  if (detail) e.detail = detail;
  return e;
}

function b64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

function bytesToB64(bytes: Uint8Array): string {
  let bin = '';
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
  if (req.method !== 'POST') return reply(405, { error: 'Use POST.' });

  const provider = (Deno.env.get('AI_PROVIDER') || DEFAULT_PROVIDER).toLowerCase();

  let payload: any;
  try { payload = await req.json(); }
  catch { return reply(400, { error: 'JSON inválido.' }); }

  if (payload.ping) {
    const keyName = provider === 'freepik' ? 'FREEPIK_API_KEY'
                  : provider === 'openai'  ? 'OPENAI_API_KEY'
                  : 'GEMINI_API_KEY';
    return reply(200, { ok: !!Deno.env.get(keyName), provider, key: keyName });
  }

  try {
    if (payload.checkTaskId) {
      const r = await freepikGetTask(payload.checkTaskId);
      if (r.status === 'COMPLETED' && r.image) return reply(200, { image: r.image });
      if (r.status === 'FAILED') throw withStatus('A IA não conseguiu gerar essa imagem. Tente um pedido diferente.', 502);
      return reply(200, { status: r.status || 'IN_PROGRESS', taskId: payload.checkTaskId });
    }

    const prompt = (payload.prompt || '').toString().trim();
    let references = Array.isArray(payload.references) ? payload.references.slice(0, 3) : [];
    const photo = payload.photo || null;
    const legacyImages = Array.isArray(payload.images) ? payload.images.slice(0, MAX_IMAGES) : [];
    if (references.length === 0 && legacyImages.length > 0) references.push(...legacyImages);
    const size = (payload.size || '').toString().trim() || null;
    if (!prompt && references.length === 0 && !photo) return reply(400, { error: 'Envie um prompt ou ao menos uma imagem.' });

    if (provider === 'freepik') {
      const taskId = await freepikCreateTask(prompt, references, photo, size);
      return reply(200, { taskId, provider: 'freepik' });
    }
    if (provider === 'openai') {
      const allImages = [...references, ...(photo ? [photo] : [])];
      const image = await generateOpenAI(prompt, allImages);
      return reply(200, { image, provider: 'openai' });
    }
    const image = await generateGemini(prompt, references, photo);
    return reply(200, { image, provider: 'gemini' });
  } catch (e: any) {
    return reply(e.status || 502, { error: e.message || 'Erro ao gerar imagem.', detail: e.detail });
  }
});

/* ===================== FREEPIK ===================== */

async function freepikCreateTask(prompt: string, references: any[], photo: any, size: string | null) {
  const KEY = Deno.env.get('FREEPIK_API_KEY');
  if (!KEY) throw withStatus('FREEPIK_API_KEY não configurada.', 500);
  const model = (Deno.env.get('FREEPIK_MODEL') || DEFAULT_FREEPIK_MODEL).toLowerCase();

  const url = model.includes('/')
    ? `https://api.freepik.com/v1/ai/${model}`
    : `https://api.freepik.com/v1/ai/text-to-image/${model}`;

  const imgSize = size || Deno.env.get('FREEPIK_IMAGE_SIZE') || '1024x1536';
  const body: Record<string, unknown> = { prompt, size: imgSize };

  if (INPUT_IMAGE_MODELS.includes(model)) {
    const src = photo || references.find((i) => i && i.data);
    if (src) body.input_image = `data:${src.mimeType || 'image/png'};base64,${src.data}`;
  } else {
    const allImgs: string[] = [];
    if (photo && photo.data) allImgs.push(photo.data);
    for (const r of references) if (r && r.data) allImgs.push(r.data);
    if (allImgs.length) body.reference_images = allImgs.slice(0, 4);
  }

  let res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-freepik-api-key': KEY },
    body: JSON.stringify(body),
  });

  if (res.status === 404) {
    const altUrl = model.includes('/')
      ? `https://api.freepik.com/v1/ai/text-to-image/${model.split('/').pop()}`
      : `https://api.freepik.com/v1/ai/${model}`;
    res = await fetch(altUrl, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'x-freepik-api-key': KEY },
      body: JSON.stringify(body),
    });
  }

  const json: any = await res.json().catch(() => ({}));
  if (!res.ok) throw withStatus((json.detail || json.error || json.message) || `Freepik retornou ${res.status} para modelo "${model}".`, res.status);
  const taskId = json?.data?.task_id;
  if (!taskId) throw withStatus(`Freepik não devolveu task_id para modelo "${model}".`, 502);
  return taskId;
}

async function freepikGetTask(taskId: string) {
  const KEY = Deno.env.get('FREEPIK_API_KEY');
  if (!KEY) throw withStatus('FREEPIK_API_KEY não configurada.', 500);
  const model = (Deno.env.get('FREEPIK_MODEL') || DEFAULT_FREEPIK_MODEL).toLowerCase();

  const urls = [
    `https://api.freepik.com/v1/ai/text-to-image/${model}/${encodeURIComponent(taskId)}`,
    `https://api.freepik.com/v1/ai/${model}/${encodeURIComponent(taskId)}`,
  ];

  let res!: Response;
  for (const url of urls) {
    res = await fetch(url, { headers: { 'x-freepik-api-key': KEY } });
    if (res.status !== 404) break;
  }
  const json: any = await res.json().catch(() => ({}));
  if (!res.ok) throw withStatus(json.detail || json.error || json.message || `Freepik retornou ${res.status}.`, res.status);

  const data = json.data || {};
  const status = data.status;
  const imgUrl = Array.isArray(data.generated) && data.generated[0];
  if (status === 'COMPLETED' && imgUrl) {
    const image = await downloadAsInline(imgUrl);
    return { status, image };
  }
  return { status };
}

async function downloadAsInline(url: string) {
  const res = await fetch(url);
  if (!res.ok) throw withStatus(`Erro ao baixar imagem gerada (${res.status}).`, 502);
  const buf = new Uint8Array(await res.arrayBuffer());
  return { mimeType: res.headers.get('content-type') || 'image/png', data: bytesToB64(buf) };
}

/* ===================== GEMINI ===================== */

async function generateGemini(prompt: string, references: any[], photo: any) {
  const KEY = Deno.env.get('GEMINI_API_KEY');
  if (!KEY) throw withStatus('GEMINI_API_KEY não configurada.', 500);
  const model = Deno.env.get('GEMINI_MODEL') || DEFAULT_GEMINI_MODEL;
  const parts: any[] = [];
  if (prompt) parts.push({ text: prompt });
  if (references.length > 0) {
    parts.push({ text: '[REFERÊNCIAS DE ESTILO — copie o estilo visual destas imagens]:' });
    for (const img of references) {
      if (img && img.data) parts.push({ inline_data: { mime_type: img.mimeType || 'image/png', data: img.data } });
    }
  }
  if (photo && photo.data) {
    parts.push({ text: '[FOTO DA PESSOA — preserve este rosto fielmente na arte]:' });
    parts.push({ inline_data: { mime_type: photo.mimeType || 'image/png', data: photo.data } });
  }
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-goog-api-key': KEY },
    body: JSON.stringify({ contents: [{ role: 'user', parts }], generationConfig: { responseModalities: ['IMAGE'] } }),
  });
  const json: any = await res.json();
  if (!res.ok) throw withStatus(json?.error?.message || `Gemini retornou ${res.status}.`, res.status);
  const outParts = json?.candidates?.[0]?.content?.parts || [];
  const imgPart = outParts.find((p: any) => p && (p.inlineData || p.inline_data));
  const inline = imgPart && (imgPart.inlineData || imgPart.inline_data);
  if (!inline || !inline.data) throw withStatus('A IA não retornou imagem. Tente de novo.', 502);
  return { mimeType: inline.mimeType || inline.mime_type || 'image/png', data: inline.data };
}

/* ===================== OPENAI ===================== */

async function generateOpenAI(prompt: string, images: any[]) {
  const KEY = Deno.env.get('OPENAI_API_KEY');
  if (!KEY) throw withStatus('OPENAI_API_KEY não configurada.', 500);
  const model = Deno.env.get('OPENAI_MODEL') || DEFAULT_OPENAI_MODEL;
  if (images.length === 0) {
    const res = await fetch('https://api.openai.com/v1/images/generations', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${KEY}` },
      body: JSON.stringify({ model, prompt, n: 1, size: '1024x1536' }),
    });
    const json: any = await res.json();
    if (!res.ok) throw withStatus(json?.error?.message || `OpenAI retornou ${res.status}.`, res.status);
    const b64 = json?.data?.[0]?.b64_json;
    if (!b64) throw withStatus('A OpenAI não retornou imagem.', 502);
    return { mimeType: 'image/png', data: b64 };
  }
  const form = new FormData();
  form.append('model', model);
  form.append('prompt', prompt);
  form.append('n', '1');
  for (const img of images) {
    if (!img || !img.data) continue;
    const bin = b64ToBytes(img.data);
    form.append('image[]', new Blob([bin], { type: img.mimeType || 'image/png' }), 'ref.png');
  }
  const res = await fetch('https://api.openai.com/v1/images/edits', {
    method: 'POST',
    headers: { Authorization: `Bearer ${KEY}` },
    body: form,
  });
  const json: any = await res.json();
  if (!res.ok) throw withStatus(json?.error?.message || `OpenAI retornou ${res.status}.`, res.status);
  const b64 = json?.data?.[0]?.b64_json;
  if (!b64) throw withStatus('A OpenAI não retornou imagem.', 502);
  return { mimeType: 'image/png', data: b64 };
}

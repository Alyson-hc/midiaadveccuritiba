/**
 * Porteiro seguro da IA — roda no servidor da Netlify (a chave NUNCA vai pro navegador).
 *
 * Suporta TRÊS provedores; escolha pela env AI_PROVIDER:
 *   AI_PROVIDER = freepik   (recomendado)  → FREEPIK_API_KEY   (Gemini 2.5 Flash Image via Magnific API)
 *   AI_PROVIDER = gemini                    → GEMINI_API_KEY    (Google AI Studio direto)
 *   AI_PROVIDER = openai                    → OPENAI_API_KEY    (GPT Image)
 *
 * O Freepik é assíncrono (cria task → consulta status). O front faz dois passos:
 *   1) POST { prompt, images } → recebe { taskId } (freepik) ou { image } direto (gemini/openai)
 *   2) Se veio taskId, POST { checkTaskId } a cada poucos segundos até receber { image }
 *
 * Devolve sempre o mesmo formato no fim:  { image: { mimeType, data(base64) } }
 *
 * Env vars (Netlify → Site settings → Environment variables):
 *   AI_PROVIDER         freepik | gemini | openai    (opcional; padrão freepik)
 *   FREEPIK_API_KEY     chave da Freepik/Magnific
 *   FREEPIK_MODEL       gemini-2-5-flash-image-preview (padrão; bom pra foto+ref)
 *                       flux-kontext-pro (alternativa, só 1 referência)
 *   GEMINI_API_KEY / GEMINI_MODEL    (se usar gemini direto)
 *   OPENAI_API_KEY / OPENAI_MODEL    (se usar openai)
 */

const DEFAULT_PROVIDER = 'freepik';
const DEFAULT_FREEPIK_MODEL = 'gemini-2-5-flash-image-preview';
const DEFAULT_GEMINI_MODEL = 'gemini-3-pro-image-preview';
const DEFAULT_OPENAI_MODEL = 'gpt-image-1.5';
const MAX_IMAGES = 4;

const headers = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type',
};
const reply = (statusCode, obj) => ({ statusCode, headers, body: JSON.stringify(obj) });

exports.handler = async (event) => {
  if (event.httpMethod === 'OPTIONS') return reply(204, {});
  if (event.httpMethod !== 'POST') return reply(405, { error: 'Use POST.' });

  const provider = (process.env.AI_PROVIDER || DEFAULT_PROVIDER).toLowerCase();

  let payload;
  try { payload = JSON.parse(event.body || '{}'); }
  catch { return reply(400, { error: 'JSON inválido.' }); }

  // Modo ping: confere que a chave do provedor está configurada
  if (payload.ping) {
    const keyName = provider === 'freepik' ? 'FREEPIK_API_KEY'
                  : provider === 'openai'  ? 'OPENAI_API_KEY'
                  : 'GEMINI_API_KEY';
    return reply(200, { ok: !!process.env[keyName], provider, key: keyName });
  }

  try {
    // 2º passo do Freepik: consultar status da task
    if (payload.checkTaskId) {
      const r = await freepikGetTask(payload.checkTaskId);
      if (r.status === 'COMPLETED' && r.image) return reply(200, { image: r.image });
      if (r.status === 'FAILED') throw withStatus('A IA não conseguiu gerar essa imagem. Tente um pedido diferente.', 502);
      return reply(200, { status: r.status || 'IN_PROGRESS', taskId: payload.checkTaskId });
    }

    const prompt = (payload.prompt || '').toString().trim();
    let references = Array.isArray(payload.references) ? payload.references.slice(0, 3) : [];
    const photo = payload.photo || null;
    // Compatibilidade: se o front mandar "images" (antigo), usa como references
    const legacyImages = Array.isArray(payload.images) ? payload.images.slice(0, MAX_IMAGES) : [];
    if (references.length === 0 && legacyImages.length > 0) {
      references.push(...legacyImages);
    }
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
    // gemini direto (Google AI Studio) — melhor opção para foto+referências
    const image = await generateGemini(prompt, references, photo);
    return reply(200, { image, provider: 'gemini' });
  } catch (e) {
    return reply(e.status || 502, { error: e.message || 'Erro ao gerar imagem.', detail: e.detail });
  }
};

/* ===================== FREEPIK / MAGNIFIC (assíncrono) ===================== */

// Modelos que usam reference_images[] (base64 puro, até 3)
const REF_IMAGE_MODELS = ['gemini-2-5-flash-image-preview', 'gpt-image-2'];
// Modelos que usam input_image (dataURI única)
const INPUT_IMAGE_MODELS = ['flux-kontext-pro'];

async function freepikCreateTask(prompt, references, photo, size) {
  const KEY = process.env.FREEPIK_API_KEY;
  if (!KEY) throw withStatus('FREEPIK_API_KEY não configurada na Netlify.', 500);
  const model = (process.env.FREEPIK_MODEL || DEFAULT_FREEPIK_MODEL).toLowerCase();

  // Monta a URL — tenta 2 padrões comuns da API do Freepik/Magnific
  const url = model.includes('/')
    ? `https://api.freepik.com/v1/ai/${model}`
    : `https://api.freepik.com/v1/ai/text-to-image/${model}`;

  const imgSize = size || process.env.FREEPIK_IMAGE_SIZE || '1024x1536';
  const body = { prompt, size: imgSize };

  if (INPUT_IMAGE_MODELS.includes(model)) {
    // flux-kontext-pro: usa input_image (dataURI única)
    const src = photo || references.find(i => i && i.data);
    if (src) body.input_image = `data:${src.mimeType || 'image/png'};base64,${src.data}`;
  } else {
    // gpt-image-2 e outros: foto + referências juntas como reference_images
    // Foto vai PRIMEIRO para ter mais peso na geração
    const allImgs = [];
    if (photo && photo.data) allImgs.push(photo.data);
    for (const r of references) {
      if (r && r.data) allImgs.push(r.data);
    }
    if (allImgs.length) body.reference_images = allImgs.slice(0, 4);
  }

  let res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-freepik-api-key': KEY },
    body: JSON.stringify(body),
  });

  // Se 404, tenta o outro padrão de URL
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

  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw withStatus((json.detail || json.error || json.message) || `Freepik retornou ${res.status} para modelo "${model}".`, res.status);
  const taskId = json && json.data && json.data.task_id;
  if (!taskId) throw withStatus(`Freepik não devolveu task_id para modelo "${model}".`, 502);
  return taskId;
}

async function freepikGetTask(taskId) {
  const KEY = process.env.FREEPIK_API_KEY;
  if (!KEY) throw withStatus('FREEPIK_API_KEY não configurada.', 500);
  const model = (process.env.FREEPIK_MODEL || DEFAULT_FREEPIK_MODEL).toLowerCase();

  // Tenta os 2 padrões de URL pra consultar status
  const urls = [
    `https://api.freepik.com/v1/ai/text-to-image/${model}/${encodeURIComponent(taskId)}`,
    `https://api.freepik.com/v1/ai/${model}/${encodeURIComponent(taskId)}`,
  ];

  let res, json;
  for (const url of urls) {
    res = await fetch(url, { headers: { 'x-freepik-api-key': KEY } });
    if (res.status !== 404) break;
  }
  json = await res.json().catch(() => ({}));
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

async function downloadAsInline(url) {
  const res = await fetch(url);
  if (!res.ok) throw withStatus(`Erro ao baixar imagem gerada (${res.status}).`, 502);
  const buf = Buffer.from(await res.arrayBuffer());
  return { mimeType: res.headers.get('content-type') || 'image/png', data: buf.toString('base64') };
}

/* ===================== GEMINI (Google AI Studio direto) ===================== */

async function generateGemini(prompt, references, photo) {
  const KEY = process.env.GEMINI_API_KEY;
  if (!KEY) throw withStatus('GEMINI_API_KEY não configurada.', 500);
  const model = process.env.GEMINI_MODEL || DEFAULT_GEMINI_MODEL;
  const parts = [];
  if (prompt) parts.push({ text: prompt });
  // Referências de estilo primeiro (com rótulo)
  if (references.length > 0) {
    parts.push({ text: '[REFERÊNCIAS DE ESTILO — copie o estilo visual destas imagens]:' });
    for (const img of references) {
      if (img && img.data) parts.push({ inline_data: { mime_type: img.mimeType || 'image/png', data: img.data } });
    }
  }
  // Foto da pessoa por último (com rótulo claro)
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
  const json = await res.json();
  if (!res.ok) throw withStatus((json.error && json.error.message) || `Gemini retornou ${res.status}.`, res.status);
  const outParts = (json.candidates && json.candidates[0] && json.candidates[0].content && json.candidates[0].content.parts) || [];
  const imgPart = outParts.find((p) => p && (p.inlineData || p.inline_data));
  const inline = imgPart && (imgPart.inlineData || imgPart.inline_data);
  if (!inline || !inline.data) throw withStatus('A IA não retornou imagem. Tente de novo.', 502);
  return { mimeType: inline.mimeType || inline.mime_type || 'image/png', data: inline.data };
}

/* ===================== OPENAI (GPT Image) ===================== */

async function generateOpenAI(prompt, images) {
  const KEY = process.env.OPENAI_API_KEY;
  if (!KEY) throw withStatus('OPENAI_API_KEY não configurada.', 500);
  const model = process.env.OPENAI_MODEL || DEFAULT_OPENAI_MODEL;
  if (images.length === 0) {
    const res = await fetch('https://api.openai.com/v1/images/generations', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${KEY}` },
      body: JSON.stringify({ model, prompt, n: 1, size: '1024x1536' }),
    });
    const json = await res.json();
    if (!res.ok) throw withStatus((json.error && json.error.message) || `OpenAI retornou ${res.status}.`, res.status);
    const b64 = json.data && json.data[0] && json.data[0].b64_json;
    if (!b64) throw withStatus('A OpenAI não retornou imagem.', 502);
    return { mimeType: 'image/png', data: b64 };
  }
  const form = new FormData();
  form.append('model', model);
  form.append('prompt', prompt);
  form.append('n', '1');
  for (const img of images) {
    if (!img || !img.data) continue;
    const bin = Buffer.from(img.data, 'base64');
    form.append('image[]', new Blob([bin], { type: img.mimeType || 'image/png' }), 'ref.png');
  }
  const res = await fetch('https://api.openai.com/v1/images/edits', {
    method: 'POST',
    headers: { Authorization: `Bearer ${KEY}` },
    body: form,
  });
  const json = await res.json();
  if (!res.ok) throw withStatus((json.error && json.error.message) || `OpenAI retornou ${res.status}.`, res.status);
  const b64 = json.data && json.data[0] && json.data[0].b64_json;
  if (!b64) throw withStatus('A OpenAI não retornou imagem.', 502);
  return { mimeType: 'image/png', data: b64 };
}

function withStatus(message, status, detail) {
  const e = new Error(message); e.status = status; if (detail) e.detail = detail; return e;
}

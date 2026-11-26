// Cole ISTO no editor do Supabase Dashboard na função "dynamic-handler" (send-evolution)
// Versão que RESOLVE o número real no WhatsApp (corrige o problema do 9º dígito no Brasil).

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

const jsonHeaders = { ...cors, 'Content-Type': 'application/json' };
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: jsonHeaders });

// Gera variações BR (com e sem o 9º dígito) pra descobrir a que existe no WhatsApp
function brVariants(num: string): string[] {
  const d = num.replace(/[^0-9]/g, '');
  const out = new Set<string>([d]);
  if (d.startsWith('55') && (d.length === 12 || d.length === 13)) {
    const ddd = d.slice(2, 4);
    const rest = d.slice(4);
    if (rest.length === 9 && rest.startsWith('9')) out.add('55' + ddd + rest.slice(1)); // sem o 9
    else if (rest.length === 8) out.add('55' + ddd + '9' + rest);                        // com o 9
  }
  return [...out];
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 200, headers: cors });
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405, headers: cors });

  const URL = (Deno.env.get('EVOLUTION_URL') || 'https://evolution-api-production-92226.up.railway.app').trim().replace(/\/+$/, '');
  const INSTANCE = Deno.env.get('EVOLUTION_INSTANCE') || 'midia';
  const KEY = Deno.env.get('EVOLUTION_KEY') || '';
  if (!KEY) return json(500, { ok: false, error: 'Falta env var EVOLUTION_KEY na Supabase.' });

  let payload: any = {};
  try { payload = await req.json(); }
  catch { return json(400, { ok: false, error: 'invalid JSON' }); }

  const { number, text } = payload;
  if (!number || !text) return json(400, { ok: false, error: 'number e text são obrigatórios' });

  const cleanNumber = String(number).replace(/[^0-9]/g, '');

  try {
    // 1) Resolve o JID real no WhatsApp (testa com e sem o 9)
    let targetNumber = cleanNumber;
    let resolve: any = null;
    try {
      const variants = brVariants(cleanNumber);
      const wn = await fetch(`${URL}/chat/whatsappNumbers/${INSTANCE}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', apikey: KEY },
        body: JSON.stringify({ numbers: variants }),
      });
      const arr: any = await wn.json().catch(() => null);
      const list: any[] = Array.isArray(arr) ? arr : (arr?.numbers || []);
      resolve = list;
      const hit = list.find((x: any) => x?.exists === true || x?.exists === 'true');
      if (hit?.jid) targetNumber = String(hit.jid).replace(/@.*/, '');
      else if (list.length > 0 && list.every((x: any) => x?.exists === false)) {
        return json(200, {
          ok: false, reason: 'not_on_whatsapp',
          error: `O número ${cleanNumber} não está no WhatsApp (nem com nem sem o 9). Confira o número cadastrado.`,
          resolve: list,
        });
      }
    } catch { /* se a checagem falhar, segue com o número original */ }

    // 2) Envia pro número resolvido
    const res = await fetch(`${URL}/message/sendText/${INSTANCE}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: KEY },
      body: JSON.stringify({ number: targetNumber, text }),
    });
    const data: any = await res.json().catch(() => ({}));
    const httpOk = res.ok;
    const bodyErr = !!data.error || /error|forbidden|unauthorized/i.test(String(data.status || ''));
    const ok = httpOk && !bodyErr;
    return json(200, { ok, status: res.status, sentTo: targetNumber, resolve, response: data });
  } catch (err: any) {
    return json(500, { ok: false, error: String(err?.message || err) });
  }
});

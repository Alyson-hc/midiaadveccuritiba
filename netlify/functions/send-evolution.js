/**
 * Envia WhatsApp via Evolution API (self-hosted, totalmente automático).
 *
 * A chave FICA NO SERVIDOR (env var) — nunca vai pro navegador.
 * O front só chama: POST /.netlify/functions/send-evolution { number, text }
 *
 * Env vars (Netlify → Site settings → Environment variables):
 *   EVOLUTION_URL       ex: https://sua-instancia.up.railway.app   (sem barra no fim)
 *   EVOLUTION_INSTANCE  nome da instância criada no Evolution (ex: "igreja")
 *   EVOLUTION_KEY       apikey global (AUTHENTICATION_API_KEY)
 *
 * Requisito: instância já conectada (QR code escaneado 1x no /manager).
 * Docs: https://doc.evolution-api.com/
 */

const cors = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

exports.handler = async (event) => {
  if (event.httpMethod === 'OPTIONS') return { statusCode: 200, headers: cors, body: '' };
  if (event.httpMethod !== 'POST')    return { statusCode: 405, headers: cors, body: 'Method not allowed' };

  // URL e INSTANCE são públicos (nome do serviço + subdomínio) — fallback embutido.
  // KEY é secreta, obrigatoriamente em env var no Netlify.
  const URL      = (process.env.EVOLUTION_URL || 'https://evolution-api-production-92226.up.railway.app').replace(/\/+$/, '');
  const INSTANCE = process.env.EVOLUTION_INSTANCE || 'midia';
  const KEY      = process.env.EVOLUTION_KEY || '';
  if (!KEY) {
    return json(500, { ok: false, error: 'Falta env var EVOLUTION_KEY no Netlify (a KEY da Evolution). Site configuration → Environment variables.' });
  }

  let payload = {};
  try { payload = JSON.parse(event.body || '{}'); }
  catch { return json(400, { ok: false, error: 'invalid JSON' }); }

  const { number, text } = payload;
  if (!number || !text) return json(400, { ok: false, error: 'number e text são obrigatórios' });

  // Evolution espera número internacional só dígitos: 5541999999999
  const cleanNumber = String(number).replace(/[^0-9]/g, '');

  try {
    // 1) VERIFICA se a instância está de fato conectada ao WhatsApp (não só "ativa")
    //    Evolution às vezes mantém state:"open" mesmo depois de "device_removed" no celular.
    //    Aí a mensagem entra como PENDING e nunca chega.
    try {
      const listRes = await fetch(`${URL}/instance/fetchInstances?instanceName=${encodeURIComponent(INSTANCE)}`, {
        headers: { apikey: KEY },
      });
      const list = await listRes.json().catch(() => []);
      const inst = Array.isArray(list) ? list.find(i => i?.name === INSTANCE) : null;
      if (inst) {
        // Conectado de verdade = status "open" E tem ownerJid.
        // (disconnectionReasonCode/disconnectionAt são histórico da última
        //  queda — Evolution não zera esses campos ao reconectar)
        const truly = inst.connectionStatus === 'open' && !!inst.ownerJid;
        if (!truly) {
          return json(200, {
            ok: false,
            reason: 'disconnected',
            error: `WhatsApp da igreja está desconectado (${inst.connectionStatus || 'unknown'}). Reabra ${URL}/manager e escaneie o QR Code da instância "${INSTANCE}".`,
          });
        }
      }
    } catch { /* se o health-check falhar, segue tentando enviar mesmo assim */ }

    // 2) Envia a mensagem
    const res = await fetch(`${URL}/message/sendText/${INSTANCE}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: KEY },
      body: JSON.stringify({ number: cleanNumber, text }),
    });
    const data = await res.json().catch(() => ({}));
    // Evolution v2 devolve { key, message, status } no sucesso.
    // "PENDING" com HTTP 201 é fila normal — se a instância está conectada, entrega em segundos.
    // Qualquer HTTP >= 400 ou objeto com .error significa falha.
    const httpOk = res.ok;
    const bodyErr = !!data.error || /error|forbidden|unauthorized/i.test(String(data.status || ''));
    const ok = httpOk && !bodyErr;
    return json(200, { ok, status: res.status, response: data });
  } catch (err) {
    return json(500, { ok: false, error: String(err.message || err) });
  }
};

function json(statusCode, body) {
  return { statusCode, headers: { ...cors, 'Content-Type': 'application/json' }, body: JSON.stringify(body) };
}

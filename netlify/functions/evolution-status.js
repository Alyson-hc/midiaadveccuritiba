/**
 * Retorna se a instância do Evolution está de fato conectada no WhatsApp.
 * Usado pra mostrar banner de alerta no admin quando desconecta silenciosamente.
 *
 * GET /.netlify/functions/evolution-status
 * → { ok, connected, needsQr, managerUrl, reason }
 */
const cors = {
  'Access-Control-Allow-Origin':  '*',
  'Access-Control-Allow-Headers': 'Content-Type',
  'Access-Control-Allow-Methods': 'GET, OPTIONS',
};

exports.handler = async (event) => {
  if (event.httpMethod === 'OPTIONS') return { statusCode: 200, headers: cors, body: '' };

  const URL      = (process.env.EVOLUTION_URL || 'https://evolution-api-production-92226.up.railway.app').replace(/\/+$/, '');
  const INSTANCE = process.env.EVOLUTION_INSTANCE || 'midia';
  const KEY      = process.env.EVOLUTION_KEY || '';
  if (!KEY) {
    return json({ ok: false, error: 'Falta env var EVOLUTION_KEY no Netlify', connected: false, needsQr: false });
  }

  try {
    const res = await fetch(`${URL}/instance/fetchInstances?instanceName=${encodeURIComponent(INSTANCE)}`, {
      headers: { apikey: KEY },
    });
    const list = await res.json().catch(() => []);
    const inst = Array.isArray(list) ? list.find(i => i?.name === INSTANCE) : null;
    if (!inst) {
      return json({ ok: false, connected: false, needsQr: true, managerUrl: `${URL}/manager`, reason: 'instância não existe' });
    }
    // Verdadeiramente conectado quando:
    //  * connectionStatus é "open" E
    //  * ownerJid está presente (WhatsApp linkado ao dispositivo)
    // (disconnectionReasonCode/disconnectionAt são histórico da última queda,
    //  não refletem o estado atual — não usar como sinal de "desconectado")
    const truly = inst.connectionStatus === 'open' && !!inst.ownerJid;
    return json({
      ok: true,
      connected: truly,
      needsQr: !truly,
      managerUrl: `${URL}/manager`,
      instance: INSTANCE,
      state: inst.connectionStatus,
      disconnectionReasonCode: inst.disconnectionReasonCode,
      disconnectionDate: inst.disconnectionAt,
    });
  } catch (err) {
    return json({ ok: false, error: String(err.message || err), connected: false, needsQr: false });
  }
};

function json(body) {
  return { statusCode: 200, headers: { ...cors, 'Content-Type': 'application/json' }, body: JSON.stringify(body) };
}

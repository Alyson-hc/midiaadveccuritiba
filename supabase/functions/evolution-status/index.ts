// GET status da instância Evolution — usado no banner de alerta do admin.

import { cors } from '../_shared/cors.ts';

const jsonHeaders = { ...cors, 'Content-Type': 'application/json' };
const json = (body: unknown) =>
  new Response(JSON.stringify(body), { status: 200, headers: jsonHeaders });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 200, headers: cors });

  const URL = (Deno.env.get('EVOLUTION_URL') || 'https://evolution-api-production-92226.up.railway.app').replace(/\/+$/, '');
  const INSTANCE = Deno.env.get('EVOLUTION_INSTANCE') || 'midia';
  const KEY = Deno.env.get('EVOLUTION_KEY') || '';
  if (!KEY) {
    return json({ ok: false, error: 'Falta env var EVOLUTION_KEY na Supabase', connected: false, needsQr: false });
  }

  try {
    const res = await fetch(`${URL}/instance/fetchInstances?instanceName=${encodeURIComponent(INSTANCE)}`, {
      headers: { apikey: KEY },
    });
    const list: any = await res.json().catch(() => []);
    const inst = Array.isArray(list) ? list.find((i: any) => i?.name === INSTANCE) : null;
    if (!inst) {
      return json({ ok: false, connected: false, needsQr: true, managerUrl: `${URL}/manager`, reason: 'instância não existe' });
    }
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
  } catch (err: any) {
    return json({ ok: false, error: String(err?.message || err), connected: false, needsQr: false });
  }
});

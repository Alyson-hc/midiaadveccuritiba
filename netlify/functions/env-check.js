/**
 * Diagnóstico: mostra quais env vars a função enxerga.
 * NUNCA retorna o valor da KEY — só se ela existe e o tamanho.
 */
exports.handler = async () => {
  const urlRaw = process.env.EVOLUTION_URL || '';
  const inst   = process.env.EVOLUTION_INSTANCE || '';
  const key    = process.env.EVOLUTION_KEY || '';
  return {
    statusCode: 200,
    headers: { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' },
    body: JSON.stringify({
      EVOLUTION_URL: urlRaw ? { set: true, value: urlRaw } : { set: false },
      EVOLUTION_INSTANCE: inst ? { set: true, value: inst } : { set: false },
      EVOLUTION_KEY: key ? { set: true, length: key.length, prefix: key.slice(0, 4) + '...' } : { set: false },
      node: process.version,
      time: new Date().toISOString(),
    }),
  };
};

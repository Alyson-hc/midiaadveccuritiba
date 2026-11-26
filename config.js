/*
 * CONEXÃO COM O BANCO (Supabase)
 * ------------------------------------------------------------------
 * Este é o ÚNICO lugar pra trocar o banco. Não precisa rodar build.
 *
 * Onde pegar os dois valores:
 *   supabase.com → seu projeto → Project Settings → API
 *     - "Project URL"          → supabaseUrl
 *     - "publishable" ou "anon public" → supabaseAnonKey
 *
 * A chave "anon" é pública por natureza (vai pro navegador de qualquer
 * jeito). NUNCA coloque aqui a "secret" / "service_role".
 */
window.MM_CONFIG = {
  supabaseUrl: 'https://ntdxmfcysfxnnjkdwikc.supabase.co',
  supabaseAnonKey: 'sb_publishable_nSdC_OtTyal8cIkmUa6j1g_tZ1HFr9O',
};

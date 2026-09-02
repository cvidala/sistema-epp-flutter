// ============================================================
// TrazApp — Edge Function: subscription-check (proxy kill-switch)
//
// Proxy server-to-server hacia la API de suscripciones de MIRA/JSV. Existe para
// que la SUBSCRIPTIONS_API_KEY viva SOLO en el servidor (secret de Supabase) y
// nunca en el APK (decompilable) ni en el JS público del dashboard.
//
// Lo llaman la app (Flutter) y el dashboard tras el login, con el JWT del usuario.
// Devuelve el estado de suscripción de la empresa (por RUT). Es SOLO el
// interruptor entrar/no entrar; el gating de módulos sigue por config_modulos.
//
// FAIL-OPEN: el cliente bloquea SOLO ante `active:false` explícito. Cualquier otra
// cosa (sin key, error de red, RUT no resoluble, upstream != 200) => ok:false y
// SIN campo active => el cliente deja entrar.
//
// Deploy: supabase functions deploy subscription-check
// Secret: supabase secrets set SUBSCRIPTIONS_API_KEY=<key JSV>
// ============================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...CORS },
  });

const UPSTREAM = 'https://js-vsytem.vercel.app/api/v1/subscriptions/check';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

  // Entrada: empresaRut y/o org_id (por query o body).
  let empresaRut = '';
  let orgId = '';
  try {
    const url = new URL(req.url);
    empresaRut = (url.searchParams.get('empresaRut') ?? '').trim();
    orgId = (url.searchParams.get('org_id') ?? '').trim();
    if (req.method === 'POST') {
      const body = await req.json().catch(() => ({}));
      empresaRut = empresaRut || String((body.empresaRut as string) ?? (body.rut as string) ?? '').trim();
      orgId = orgId || String((body.org_id as string) ?? '').trim();
    }
  } catch (_) { /* ignore */ }

  const apiKey = Deno.env.get('SUBSCRIPTIONS_API_KEY') ?? '';
  if (!apiKey) {
    // Sin key configurada => fail-open (no bloquear).
    return json({ ok: false, failopen: true, reason: 'no_key' });
  }

  // Resolver RUT: si no vino, buscarlo por org_id (service_role).
  if (!empresaRut && orgId) {
    try {
      const supabase = createClient(
        Deno.env.get('SUPABASE_URL')!,
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      );
      const { data } = await supabase
        .from('organizaciones')
        .select('rut')
        .eq('org_id', orgId)
        .maybeSingle();
      empresaRut = String(data?.rut ?? '').trim();
    } catch (_) { /* ignore */ }
  }

  if (!empresaRut) {
    return json({ ok: false, failopen: true, reason: 'no_rut' });
  }

  // Consultar upstream (MIRA/JSV).
  try {
    const uri = `${UPSTREAM}?empresaRut=${encodeURIComponent(empresaRut)}&producto=trazapp`;
    const resp = await fetch(uri, {
      headers: { 'x-api-key': apiKey, 'Content-Type': 'application/json' },
      signal: AbortSignal.timeout(8000),
    });

    if (resp.status !== 200) {
      // 401/400/404/5xx => no confundir con "sin suscripción" => fail-open.
      return json({ ok: false, failopen: true, reason: `upstream_${resp.status}` });
    }

    const data = await resp.json();
    const active = (data.active as boolean | undefined) ?? undefined;
    if (active === undefined) {
      return json({ ok: false, failopen: true, reason: 'no_active_field' });
    }

    const suscripcion = (data.suscripcion as Record<string, unknown> | null) ?? null;
    return json({
      ok: true,
      active,
      planNombre: (suscripcion?.planNombre as string) ?? '',
      estado: (suscripcion?.estado as string) ?? (data.reason as string) ?? '',
    });
  } catch (_) {
    // Timeout / red => fail-open.
    return json({ ok: false, failopen: true, reason: 'fetch_error' });
  }
});

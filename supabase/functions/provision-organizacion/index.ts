// ============================================================
// TrazApp — Edge Function: provision-organizacion
// Aprovisiona una empresa nueva: crea la organización + el usuario ADMIN.
// La llama MIRA (server-to-server) al dar de alta la empresa en /superadmin.
//
// Contrato: docs/PROVISIONING-API.md
// Auth: secreto compartido en header `x-trazapp-provision-key`
//       (validado contra el secret TRAZAPP_PROVISION_KEY).
// Idempotente por RUT: si la org ya existe, no la duplica; en re-aprovisionamiento
// actualiza config_modulos (propaga cambios de plan desde MIRA).
// Deploy: supabase functions deploy provision-organizacion --no-verify-jwt
// ============================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });

// Contraseña temporal robusta (cumple políticas: mayúsc + minúsc + dígito + símbolo).
function tempPassword(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(16));
  const b64 = btoa(String.fromCharCode(...bytes)).replace(/[^a-zA-Z0-9]/g, '');
  return `Tz${b64.slice(0, 14)}9!`;
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return json({ ok: true });
  if (req.method !== 'POST') return json({ ok: false, error: 'method_not_allowed' }, 405);

  // ── Auth: secreto compartido ──────────────────────────────
  const expected = Deno.env.get('TRAZAPP_PROVISION_KEY') ?? '';
  const provided = req.headers.get('x-trazapp-provision-key') ?? '';
  if (!expected || provided.length !== expected.length || provided !== expected) {
    return json({ ok: false, error: 'unauthorized', code: 'AUTH' }, 401);
  }

  // ── Parse + validación ────────────────────────────────────
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: 'invalid_json', code: 'BAD_REQUEST' }, 400);
  }

  const rut = String((body.rut as string) ?? '').trim();
  const razon = String((body.razon_social as string) ?? '').trim();
  const admin = (body.admin as Record<string, unknown>) ?? {};
  const adminEmail = String((admin.email as string) ?? '').trim().toLowerCase();
  const adminNombre = String((admin.nombre as string) ?? '').trim();
  // config_modulos: contrato canónico de 9 llaves booleanas (fuente de verdad = MIRA).
  // Se guarda TAL CUAL llega en el body (sin remapear ni filtrar llaves). El default
  // solo aplica si MIRA no envía config_modulos (red de seguridad, plan base EPP).
  const modulos = (body.config_modulos as Record<string, boolean>) ?? {
    gestion_epp: true,
    marcaje_asistencia: false,
    stock_bodega: true,
    solicitudes_epp: true,
    firma_digital: true,
    reportes_dt: true,
    dashboard: true,
    prevencion: false,
    contratos: false,
  };

  if (!rut || !razon || !adminEmail || !adminNombre) {
    return json({ ok: false, error: 'missing_fields', code: 'VALIDATION' }, 400);
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  );

  try {
    // ── 1) Organización (idempotente por RUT) ───────────────
    const { data: existing } = await supabase
      .from('organizaciones')
      .select('org_id')
      .eq('rut', rut)
      .maybeSingle();

    let orgId = existing?.org_id as string | undefined;
    const dedupOrg = !!orgId;
    const accion = dedupOrg ? 'updated' : 'created';

    if (!orgId) {
      const { data: orgIns, error: orgErr } = await supabase
        .from('organizaciones')
        .insert({
          rut,
          rut_empresa: rut,
          razon_social: razon,
          nombre_empresa: razon,
          config_modulos: modulos,
          activo: true,
        })
        .select('org_id')
        .single();
      if (orgErr) return json({ ok: false, error: 'org_insert_failed', detail: orgErr.message }, 500);
      orgId = orgIns.org_id as string;
    } else {
      // Org ya existe (re-aprovisionamiento): propagar el plan actualizando SOLO
      // config_modulos. No se tocan razon_social/activo/otros campos para no
      // pisar cambios hechos desde el dashboard. Así un cambio de plan en MIRA
      // se refleja en TrazApp con un re-aprovisionamiento explícito.
      const { error: updErr } = await supabase
        .from('organizaciones')
        .update({ config_modulos: modulos })
        .eq('org_id', orgId);
      if (updErr) return json({ ok: false, error: 'org_update_failed', detail: updErr.message }, 500);
    }

    // ── 2) Usuario ADMIN en Auth ────────────────────────────
    const pwd = tempPassword();
    let adminUserId: string | undefined;
    let dedupUser = false;

    const { data: created, error: createErr } = await supabase.auth.admin.createUser({
      email: adminEmail,
      password: pwd,
      email_confirm: true,
      user_metadata: { nombre: adminNombre, rol: 'ADMIN' },
    });

    if (createErr) {
      // Ya existía en Auth → lo buscamos (defensivo; en alta nueva no debería pasar).
      if (/registered|already|exists/i.test(createErr.message)) {
        const { data: list } = await supabase.auth.admin.listUsers({ page: 1, perPage: 200 });
        const found = list?.users?.find(
          (u) => (u.email ?? '').toLowerCase() === adminEmail,
        );
        adminUserId = found?.id;
        dedupUser = true;
        if (!adminUserId) {
          return json({ ok: false, error: 'admin_exists_but_not_found', code: 'ADMIN_LOOKUP' }, 409);
        }
      } else {
        return json({ ok: false, error: 'admin_create_failed', detail: createErr.message }, 500);
      }
    } else {
      adminUserId = created.user!.id;
    }

    // ── 3) Perfil ADMIN (upsert idempotente) ────────────────
    const { error: perfilErr } = await supabase
      .from('perfiles')
      .upsert(
        {
          user_id: adminUserId,
          nombre: adminNombre,
          rol: 'ADMIN',
          org_id: orgId,
          activo: true,
        },
        { onConflict: 'user_id' },
      );
    if (perfilErr) return json({ ok: false, error: 'perfil_failed', detail: perfilErr.message }, 500);

    // ── Respuesta ───────────────────────────────────────────
    return json({
      ok: true,
      org_id: orgId,
      admin_user_id: adminUserId,
      dedup: dedupOrg,
      accion, // 'created' (org nueva) | 'updated' (re-aprovisionamiento: config_modulos actualizado)
      credenciales: dedupUser
        ? { email: adminEmail, modo: 'existente' }
        : { email: adminEmail, password_temporal: pwd, modo: 'password_temporal' },
    });
  } catch (e) {
    return json({ ok: false, error: 'internal', detail: String(e) }, 500);
  }
});

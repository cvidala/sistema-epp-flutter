// ============================================================
// TrazApp — Edge Function: notif-vencimiento
// Corre diariamente (pg_cron 8:00 AM UTC).
// Detecta EPP próximos a vencer y envía emails via Resend.
// ============================================================
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL            = Deno.env.get('SUPABASE_URL')!;
const SUPABASE_SERVICE_KEY    = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const RESEND_API_KEY          = Deno.env.get('RESEND_API_KEY')!;
const FROM_EMAIL              = 'TrazApp <notificaciones@trazapp.cl>';
const DASHBOARD_URL           = 'https://trazapp.cl';

interface Vencimiento {
  org_id:           string;
  trabajador_nombre: string;
  trabajador_rut:   string;
  obra_nombre:      string;
  epp_nombre:       string;
  epp_codigo:       string;
  dias_restantes:   number;
  fecha_vencimiento: string;
  nivel_alerta:     'CRITICO' | 'AVISO';
}

interface Destinatario {
  nombre:     string;
  email_notif: string | null;
}

Deno.serve(async () => {
  try {
    const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    // ── 1. Obtener vencimientos del día ──────────────────
    const { data: venc, error: vErr } = await sb
      .rpc('get_vencimientos_proximos');
    if (vErr) throw new Error(`RPC error: ${vErr.message}`);
    if (!venc || venc.length === 0) {
      return new Response('Sin vencimientos para notificar hoy.', { status: 200 });
    }

    // ── 2. Agrupar por organización ──────────────────────
    const porOrg = new Map<string, Vencimiento[]>();
    for (const v of venc as Vencimiento[]) {
      if (!porOrg.has(v.org_id)) porOrg.set(v.org_id, []);
      porOrg.get(v.org_id)!.push(v);
    }

    // ── 3. Para cada org: obtener destinatarios y enviar ─
    let emailsEnviados = 0;
    const errores: string[] = [];

    for (const [orgId, items] of porOrg) {
      const { data: destinatarios, error: dErr } = await sb
        .from('perfiles')
        .select('nombre, email_notif')
        .eq('org_id', orgId)
        .eq('recibe_notif_venc', true)
        .eq('activo', true);

      if (dErr || !destinatarios?.length) continue;

      const emails = (destinatarios as Destinatario[])
        .map(d => d.email_notif)
        .filter((e): e is string => !!e && e.includes('@'));

      if (!emails.length) continue;

      const criticos = items.filter(i => i.nivel_alerta === 'CRITICO');
      const avisos   = items.filter(i => i.nivel_alerta === 'AVISO');
      const asunto   = criticos.length > 0
        ? `🔴 ${criticos.length} EPP vence${criticos.length > 1 ? 'n' : ''} en ${criticos[0].dias_restantes} días — TrazApp`
        : `⚠️ ${avisos.length} EPP próximo${avisos.length > 1 ? 's' : ''} a vencer — TrazApp`;

      const html = buildEmailHtml(items, criticos, avisos);

      const res = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${RESEND_API_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ from: FROM_EMAIL, to: emails, subject: asunto, html }),
      });

      if (!res.ok) {
        const err = await res.text();
        errores.push(`Org ${orgId}: ${err}`);
      } else {
        emailsEnviados++;
      }
    }

    const msg = `Enviados: ${emailsEnviados} emails. Errores: ${errores.length > 0 ? errores.join(' | ') : 'ninguno'}.`;
    console.log(msg);
    return new Response(msg, { status: 200 });

  } catch (e) {
    console.error('Error en notif-vencimiento:', e);
    return new Response(`Error: ${e.message}`, { status: 500 });
  }
});

// ── Template de email ──────────────────────────────────────
function buildEmailHtml(
  todos: Vencimiento[],
  criticos: Vencimiento[],
  avisos: Vencimiento[]
): string {
  const today = new Date().toLocaleDateString('es-CL', {
    weekday: 'long', year: 'numeric', month: 'long', day: 'numeric'
  });

  const filas = (items: Vencimiento[], color: string, icono: string) =>
    items.map(v => `
      <tr>
        <td style="padding:10px 12px;border-bottom:1px solid #eee;font-size:13px;">${icono} ${v.epp_nombre} <span style="font-size:11px;color:#888;">(${v.epp_codigo})</span></td>
        <td style="padding:10px 12px;border-bottom:1px solid #eee;font-size:13px;">${v.trabajador_nombre}<br><span style="font-size:11px;color:#888;">${v.trabajador_rut}</span></td>
        <td style="padding:10px 12px;border-bottom:1px solid #eee;font-size:13px;">${v.obra_nombre}</td>
        <td style="padding:10px 12px;border-bottom:1px solid #eee;font-size:13px;font-weight:700;color:${color};">${v.dias_restantes} días</td>
        <td style="padding:10px 12px;border-bottom:1px solid #eee;font-size:12px;color:#666;">${formatFecha(v.fecha_vencimiento)}</td>
      </tr>`).join('');

  const seccionCriticos = criticos.length > 0 ? `
    <h3 style="font-size:14px;font-weight:700;color:#dc2626;margin:24px 0 8px;">🔴 Vencimiento crítico (≤7 días)</h3>
    <table width="100%" cellspacing="0" cellpadding="0" style="border-collapse:collapse;border:1px solid #fecaca;border-radius:8px;overflow:hidden;">
      <thead><tr style="background:#fef2f2;">
        <th style="padding:8px 12px;text-align:left;font-size:11px;color:#dc2626;font-weight:700;">EPP</th>
        <th style="padding:8px 12px;text-align:left;font-size:11px;color:#dc2626;font-weight:700;">TRABAJADOR</th>
        <th style="padding:8px 12px;text-align:left;font-size:11px;color:#dc2626;font-weight:700;">CENTRO</th>
        <th style="padding:8px 12px;text-align:left;font-size:11px;color:#dc2626;font-weight:700;">DÍAS</th>
        <th style="padding:8px 12px;text-align:left;font-size:11px;color:#dc2626;font-weight:700;">VENCE</th>
      </tr></thead>
      <tbody>${filas(criticos, '#dc2626', '🔴')}</tbody>
    </table>` : '';

  const seccionAvisos = avisos.length > 0 ? `
    <h3 style="font-size:14px;font-weight:700;color:#d97706;margin:24px 0 8px;">⚠️ Aviso anticipado</h3>
    <table width="100%" cellspacing="0" cellpadding="0" style="border-collapse:collapse;border:1px solid #fde68a;border-radius:8px;overflow:hidden;">
      <thead><tr style="background:#fffbeb;">
        <th style="padding:8px 12px;text-align:left;font-size:11px;color:#d97706;font-weight:700;">EPP</th>
        <th style="padding:8px 12px;text-align:left;font-size:11px;color:#d97706;font-weight:700;">TRABAJADOR</th>
        <th style="padding:8px 12px;text-align:left;font-size:11px;color:#d97706;font-weight:700;">CENTRO</th>
        <th style="padding:8px 12px;text-align:left;font-size:11px;color:#d97706;font-weight:700;">DÍAS</th>
        <th style="padding:8px 12px;text-align:left;font-size:11px;color:#d97706;font-weight:700;">VENCE</th>
      </tr></thead>
      <tbody>${filas(avisos, '#d97706', '⚠️')}</tbody>
    </table>` : '';

  return `<!DOCTYPE html>
<html lang="es"><head><meta charset="UTF-8"></head>
<body style="margin:0;padding:0;background:#f4f6fb;font-family:'Segoe UI',Arial,sans-serif;">
<table width="100%" cellspacing="0" cellpadding="0"><tr><td style="padding:32px 16px;">
  <table width="600" cellspacing="0" cellpadding="0" align="center" style="background:white;border-radius:16px;overflow:hidden;box-shadow:0 4px 24px rgba(0,0,0,0.08);">
    <!-- Header -->
    <tr><td style="background:#0D2148;padding:28px 32px;">
      <table width="100%" cellspacing="0"><tr>
        <td>
          <div style="display:inline-block;background:#E87722;border-radius:10px;width:36px;height:36px;text-align:center;line-height:36px;font-size:18px;vertical-align:middle;margin-right:10px;">🦺</div>
          <span style="font-size:20px;font-weight:700;color:white;vertical-align:middle;">TrazApp</span>
          <span style="font-size:11px;color:rgba(255,255,255,0.5);margin-left:8px;vertical-align:middle;letter-spacing:2px;text-transform:uppercase;">EPP</span>
        </td>
      </tr></table>
    </td></tr>
    <!-- Body -->
    <tr><td style="padding:32px;">
      <p style="font-size:13px;color:#6B7A99;margin:0 0 4px;">Reporte diario · ${today}</p>
      <h2 style="font-size:20px;font-weight:700;color:#0D2148;margin:0 0 8px;">
        ${todos.length} EPP próximo${todos.length > 1 ? 's' : ''} a vencer
      </h2>
      <p style="font-size:13px;color:#6B7A99;margin:0 0 24px;">
        A continuación los equipos de protección que requieren atención.
      </p>
      ${seccionCriticos}
      ${seccionAvisos}
      <!-- CTA -->
      <div style="text-align:center;margin:32px 0 0;">
        <a href="${DASHBOARD_URL}" style="display:inline-block;background:#E87722;color:white;font-size:14px;font-weight:700;padding:12px 32px;border-radius:10px;text-decoration:none;">
          Ver en Dashboard →
        </a>
      </div>
    </td></tr>
    <!-- Footer -->
    <tr><td style="background:#f8fafc;padding:20px 32px;border-top:1px solid #e8edf5;">
      <p style="font-size:11px;color:#9BA8BF;margin:0;text-align:center;">
        TrazApp · Sistema de Control de EPP · <a href="${DASHBOARD_URL}" style="color:#E87722;">trazapp.cl</a><br>
        Para no recibir estas notificaciones, pide a tu administrador desactivarlas en Usuarios → Notificaciones.
      </p>
    </td></tr>
  </table>
</td></tr></table>
</body></html>`;
}

function formatFecha(iso: string): string {
  return new Date(iso + 'T12:00:00').toLocaleDateString('es-CL', {
    day: '2-digit', month: 'short', year: 'numeric'
  });
}

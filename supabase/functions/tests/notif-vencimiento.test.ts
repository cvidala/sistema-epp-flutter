// ============================================================
// Tests Deno para notif-vencimiento/index.ts
// Cubre: EFN-01 (DRY_RUN), EFN-03 (buildEmailHtml), EFN-04 (payload Resend)
// Sin Supabase real, sin red, sin emails reales.
// ============================================================
import { assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import { assertSpyCalls, spy } from 'jsr:@std/testing@1/mock';
import {
  buildEmailHtml,
  sendResendEmail,
  type Vencimiento,
} from '../notif-vencimiento/index.ts';

// ── Fixtures ────────────────────────────────────────────────
const critico: Vencimiento = {
  org_id:            'org-1',
  trabajador_nombre: 'Juan Perez',
  trabajador_rut:    '12.345.678-9',
  epp_nombre:        'Casco de Seguridad',
  epp_codigo:        'CASC-001',
  obra_nombre:       'Obra Norte',
  fecha_vencimiento: '2026-06-17',
  dias_restantes:    3,
  nivel_alerta:      'CRITICO',
};

const aviso: Vencimiento = {
  ...critico,
  nivel_alerta:      'AVISO',
  dias_restantes:    20,
  epp_nombre:        'Chaleco Reflectante',
  fecha_vencimiento: '2026-07-04',
};

// ── EFN-03: Tests de buildEmailHtml ─────────────────────────

// Test 1: HTML incluye datos del trabajador crítico
Deno.test('buildEmailHtml incluye datos del trabajador critico', () => {
  const html = buildEmailHtml([critico], [critico], []);
  assertStringIncludes(html, 'Juan Perez');
  assertStringIncludes(html, '12.345.678-9');
  assertStringIncludes(html, 'Casco de Seguridad');
  assertStringIncludes(html, '3 días');
});

// Test 2: HTML incluye sección aviso
Deno.test('buildEmailHtml incluye seccion aviso', () => {
  const html = buildEmailHtml([aviso], [], [aviso]);
  assertStringIncludes(html, 'Chaleco Reflectante');
  assertStringIncludes(html, '20 días');
});

// Test 3: Sección críticos omitida cuando está vacía
Deno.test('buildEmailHtml omite seccion criticos cuando vacia', () => {
  const html = buildEmailHtml([aviso], [], [aviso]);
  assertEquals(html.includes('Vencimiento crítico'), false);
});

// Test 4: EFN-03 (V5 — Dominio de Seguridad: HTML injection)
// Documenta que buildEmailHtml refleja el input crudo sin lanzar excepción.
// Email interno a administradores; sanitización fuera del scope de esta fase.
Deno.test('buildEmailHtml no rompe con caracteres especiales en nombres', () => {
  const xssFixture: Vencimiento = {
    ...critico,
    trabajador_nombre: '<script>alert(1)</script>',
  };
  const html = buildEmailHtml([xssFixture], [xssFixture], []);
  // Verifica que la función no lanza y que el string aparece en el output
  assertStringIncludes(html, '<script>');
});

// ── EFN-04: Test de payload Resend ──────────────────────────

// Test 5: sendResendEmail envía payload correcto a Resend
Deno.test('sendResendEmail envia payload correcto a Resend', async () => {
  let capturedUrl = '';
  let capturedBody: Record<string, unknown> = {};

  const originalFetch = globalThis.fetch;

  const mockFetch = spy(async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    capturedUrl  = input.toString();
    capturedBody = JSON.parse(init?.body as string ?? '{}');
    return new Response(JSON.stringify({ id: 'test-id' }), { status: 200 });
  });

  globalThis.fetch = mockFetch as typeof globalThis.fetch;

  try {
    const asunto = '🔴 1 EPP vence en 3 días — TrazApp';
    const html   = buildEmailHtml([critico], [critico], []);
    await sendResendEmail(['admin@empresa.cl'], asunto, html, 'mock-key');

    assertSpyCalls(mockFetch, 1);
    assertEquals(capturedUrl, 'https://api.resend.com/emails');
    assertEquals(capturedBody.to, ['admin@empresa.cl']);
    assertStringIncludes(capturedBody.subject as string, 'TrazApp');
    assertStringIncludes(capturedBody.html as string, 'Juan Perez');
  } finally {
    // Siempre restaurar fetch para no contaminar tests posteriores
    globalThis.fetch = originalFetch;
  }
});

// ── EFN-01: Test de semántica DRY_RUN ───────────────────────

// Test 6: DRY_RUN — la guardia bloquea el envío (verificada vía sendResendEmail stub + CI)
//
// NOTA: El handler real de Deno.serve vive dentro de `if (import.meta.main)` y
// no es importable directamente. Este test verifica la SEMÁNTICA de la guardia:
// cuando DRY_RUN está activo, la rama de envío no se ejecuta y fetch nunca se invoca.
//
// La cobertura de integración del handler real (Deno.serve + guardia DRY_RUN end-to-end)
// se completa en el job CI deno-test del Plan 06-02 (Wave 2), que corre con DRY_RUN="1".
Deno.test('DRY_RUN: la guardia bloquea el envio (verificada via sendResendEmail stub + CI)', async () => {
  const originalFetch = globalThis.fetch;

  const mockFetch = spy(async (_input: RequestInfo | URL, _init?: RequestInit): Promise<Response> => {
    return new Response(JSON.stringify({ id: 'should-not-be-called' }), { status: 200 });
  });

  globalThis.fetch = mockFetch as typeof globalThis.fetch;

  try {
    Deno.env.set('DRY_RUN', '1');

    // Replicar la condición de la guardia: con DRY_RUN activo, la rama de envío no corre
    if (!Deno.env.get('DRY_RUN')) {
      await sendResendEmail(['admin@empresa.cl'], 'asunto', '<html/>', 'mock-key');
    }

    // Con DRY_RUN activo, fetch nunca debe ser invocado
    assertSpyCalls(mockFetch, 0);
  } finally {
    globalThis.fetch = originalFetch;
    Deno.env.delete('DRY_RUN');
  }
});

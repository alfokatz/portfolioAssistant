// E2E de Porty: maneja la app web real (build/web) contra el Supabase local
// con Playwright, como lo haría una persona. Lo corre tools/verify/e2e/run.sh.
//
// Cada flujo es una lista de pasos con nombre. Si un paso falla, se guarda una
// captura y el reporte dice QUÉ paso falló (no solo "timeout").
//
// Variables: E2E_URL (app servida), E2E_EMAIL, E2E_PASSWORD, E2E_OUT (carpeta
// de capturas), E2E_FLOWS (lista separada por comas; vacío = todos).
import { createRequire } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';

// Playwright está preinstalado de forma global en el entorno: `require` (a
// diferencia de `import`) respeta NODE_PATH, que run.sh apunta a npm root -g.
const { chromium } = createRequire(import.meta.url)('playwright');

const URL = process.env.E2E_URL ?? 'http://127.0.0.1:8099';
const EMAIL = process.env.E2E_EMAIL;
const PASSWORD = process.env.E2E_PASSWORD;
const OUT = process.env.E2E_OUT ?? 'build/e2e';
const ONLY = (process.env.E2E_FLOWS ?? '').split(',').map((s) => s.trim()).filter(Boolean);
const STEP_TIMEOUT = 20_000;

fs.mkdirSync(OUT, { recursive: true });

// Flutter web dibuja en un canvas: para encontrar textos y botones hay que
// prender el árbol de semántica (el botón oculto que pone el engine).
async function enableSemantics(page) {
  await page.waitForSelector('flt-semantics-placeholder, flt-glass-pane, flutter-view', {
    state: 'attached',
    timeout: 60_000,
  });
  await page.evaluate(() => {
    const p = document.querySelector('flt-semantics-placeholder');
    if (p) p.click();
  });
}

const text = (page, t) => page.getByText(t, { exact: false }).first();

// Espera a que un texto aparezca en pantalla, sea como texto o como etiqueta
// accesible (Flutter a veces junta varios textos en un solo aria-label).
async function seen(page, t, timeout = STEP_TIMEOUT) {
  await page.waitForFunction(
    (needle) =>
      document.body.innerText.includes(needle) ||
      [...document.querySelectorAll('[aria-label]')].some((e) => e.getAttribute('aria-label').includes(needle)),
    t,
    { timeout },
  );
}

// Escribe en un campo como una persona: lo toca, espera a que Flutter lo
// enfoque y tipea. Con `fill()` directo, el primer campo de un formulario a
// veces pierde el valor (Flutter web todavía no había conectado el input al
// teclado): por eso se tipea y después se comprueba lo que quedó.
async function typeInto(page, locator, value) {
  await locator.click();
  await page.waitForFunction(
    () => document.activeElement && ['INPUT', 'TEXTAREA'].includes(document.activeElement.tagName),
    null,
    { timeout: 5_000 },
  );
  await page.keyboard.press('Control+A');
  await page.keyboard.type(value, { delay: 15 });
  const got = await locator.inputValue();
  if (got !== value) throw new Error(`el campo quedó con "${got}" en vez de "${value}"`);
}

// Los campos del login no tienen etiqueta accesible (solo placeholder), así
// que se ubican por tipo de input.
async function fillLogin(page, email, password) {
  const emailInput = page.locator('input[type="email"], input[type="text"]').first();
  const passwordInput = page.locator('input[type="password"]').first();
  await typeInto(page, emailInput, email);
  await typeInto(page, passwordInput, password);
}

async function openLogin(page) {
  await page.goto(URL);
  await enableSemantics(page);
  await page.locator('input[type="password"]').first().waitFor({ state: 'attached', timeout: 60_000 });
  // Esperar al formulario completo (idioma cargado y animación de entrada).
  await seen(page, 'o continuá con', 30_000);
  await page.waitForLoadState('networkidle');
}

async function signIn(page) {
  await openLogin(page);
  await fillLogin(page, EMAIL, PASSWORD);
  await submitLogin(page);
}

async function submitLogin(page) {
  // El botón principal del formulario (no la pestaña "Iniciar sesión").
  const buttons = page.getByRole('button', { name: /^Iniciar sesión$/ });
  await buttons.last().click();
}

const role = (page, r, name) => page.getByRole(r, { name }).first();

// Las listas de Flutter construyen lo que está en pantalla: para llegar a un
// botón de más abajo hay que scrollear con la rueda, no con scrollIntoView.
async function scrollTo(page, name, maxScrolls = 15) {
  const target = page.getByRole('button', { name }).first();
  for (let i = 0; i < maxScrolls; i++) {
    if (await target.count()) return target;
    await page.mouse.move(195, 420);
    await page.mouse.wheel(0, 500);
    await page.waitForTimeout(300);
  }
  throw new Error(`no encontré "${name}" scrolleando`);
}

// Un usuario nuevo (run.sh crea uno por corrida) pasa por el onboarding.
async function skipOnboarding(page) {
  await role(page, 'button', /^Empezar/).waitFor({ timeout: 45_000 });
  await role(page, 'button', /^Empezar/).click();
  await role(page, 'button', /^Ahora no/).click();
}

async function goHome(page) {
  await signIn(page);
  await skipOnboarding(page);
  await text(page, 'Mis posiciones').waitFor({ timeout: 30_000 });
}

// ── Flujos ──────────────────────────────────────────────────────────────────
// Agregar uno: { name, steps: [[descripción, async (page) => {...}], ...] }.
// Que cada paso diga lo que ve el usuario, no detalles de implementación.
const FLOWS = [
  {
    name: 'arranque',
    steps: [
      ['abre la app', async (page) => { await page.goto(URL); await enableSemantics(page); }],
      ['muestra el login de Porty', async (page) => text(page, 'Iniciar sesión').waitFor({ timeout: 60_000 })],
    ],
  },
  {
    name: 'login-clave-incorrecta',
    steps: [
      ['abre la app', openLogin],
      ['completa email y contraseña equivocada', async (page) => fillLogin(page, EMAIL, 'NoEsLaClave123')],
      ['toca Iniciar sesión', submitLogin],
      ['ve el error de credenciales', async (page) => text(page, 'no son correctos').waitFor()],
    ],
  },
  {
    name: 'login-onboarding-home',
    steps: [
      ['inicia sesión con el usuario de prueba', signIn],
      ['ve el onboarding y toca Empezar', async (page) => {
        await role(page, 'button', /^Empezar/).waitFor({ timeout: 45_000 });
        await role(page, 'button', /^Empezar/).click();
      }],
      ['elige "Ahora no" para cargar la cartera', async (page) => role(page, 'button', /^Ahora no/).click()],
      ['llega al inicio con la cartera vacía', async (page) => {
        await text(page, 'Mis posiciones').waitFor({ timeout: 30_000 });
        await text(page, '0 posiciones').waitFor();
      }],
    ],
  },
  {
    name: 'cargar-posicion-a-mano',
    steps: [
      ['inicia sesión y pasa al onboarding', async (page) => {
        await signIn(page);
        await role(page, 'button', /^Empezar/).waitFor({ timeout: 45_000 });
        await role(page, 'button', /^Empezar/).click();
      }],
      ['elige "Cargala a mano"', async (page) => role(page, 'button', /^Cargala a mano/).click()],
      ['completa ticker, precio y cantidad', async (page) => {
        await typeInto(page, role(page, 'textbox', /Ticker/), 'AAPL');
        await typeInto(page, role(page, 'textbox', /Precio de compra/), '150');
        await typeInto(page, role(page, 'textbox', /Cantidad/), '10');
      }],
      ['toca "Agregar a mi cartera"', async (page) => role(page, 'button', /^Agregar a mi cartera/).click()],
      ['la posición aparece en el inicio', async (page) => {
        await text(page, 'Mis posiciones').waitFor({ timeout: 30_000 });
        await text(page, 'AAPL').waitFor({ timeout: 30_000 });
      }],
    ],
  },
  {
    name: 'ajustes-y-cerrar-sesion',
    steps: [
      ['entra al inicio', goHome],
      ['abre Ajustes', async (page) => role(page, 'button', /^Ajustes/).click()],
      ['ve su email en Ajustes', async (page) => seen(page, EMAIL)],
      ['baja hasta Cerrar sesión y lo toca', async (page) => {
        const b = await scrollTo(page, /Cerrar sesión/);
        await b.click();
        // Puede pedir confirmación en una hoja: el último botón con ese nombre.
        await page.waitForTimeout(800);
        const confirm = page.getByRole('button', { name: /Cerrar sesión/ });
        if ((await confirm.count()) > 1) await confirm.last().click();
      }],
      ['vuelve al login', async (page) =>
        page.locator('input[type="password"]').first().waitFor({ state: 'attached', timeout: 30_000 })],
    ],
  },
];

// ── Runner ──────────────────────────────────────────────────────────────────
const browser = await chromium.launch();
const results = [];
for (const flow of FLOWS) {
  if (ONLY.length && !ONLY.includes(flow.name)) continue;
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, locale: 'es-ES' });
  const page = await context.newPage();
  page.setDefaultTimeout(STEP_TIMEOUT);
  const consoleErrors = [];
  page.on('console', (m) => { if (m.type() === 'error') consoleErrors.push(m.text()); });
  page.on('pageerror', (e) => consoleErrors.push(String(e)));

  const done = [];
  let failure = null;
  for (const [desc, fn] of flow.steps) {
    try {
      await fn(page);
      done.push(desc);
    } catch (e) {
      const shot = path.join(OUT, `${flow.name}-FALLA.png`);
      await page.screenshot({ path: shot }).catch(() => {});
      failure = { step: desc, error: String(e.message ?? e).split('\n')[0], screenshot: shot };
      break;
    }
  }
  if (!failure) await page.screenshot({ path: path.join(OUT, `${flow.name}-ok.png`) }).catch(() => {});
  results.push({ flow: flow.name, ok: !failure, done, failure, consoleErrors: consoleErrors.slice(0, 5) });
  await context.close();
}
await browser.close();

console.log('\n──────── E2E ────────');
for (const r of results) {
  if (r.ok) {
    console.log(`✓ ${r.flow} (${r.done.length} pasos)`);
  } else {
    console.log(`✗ ${r.flow}`);
    for (const d of r.done) console.log(`    ✓ ${d}`);
    console.log(`    ✗ ${r.failure.step}: ${r.failure.error}`);
    console.log(`      captura: ${r.failure.screenshot}`);
    for (const c of r.consoleErrors) console.log(`      consola: ${c.slice(0, 200)}`);
  }
}
fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify(results, null, 2));
process.exit(results.every((r) => r.ok) ? 0 : 1);

// Genera un clip con la API de Sunra (cola: submit → status → result) y lo baja.
// La autenticación la agrega el proxy del entorno (secreto de red para
// api.sunra.ai): este script no lee ninguna key.
//
// Uso: node tools/marketing/video/sunra_gen.mjs <endpoint> <input.json> <salida>
//   endpoint: p. ej. bytedance/seedance-2.0/text-to-video
//   input.json: el cuerpo del pedido según el OpenAPI del modelo
//   (https://oapi.sunra.ai/main/<owner>/<model>/latest.json).
import { readFileSync, writeFileSync } from 'node:fs';

const [endpoint, inputPath, out] = process.argv.slice(2);
if (!endpoint || !inputPath || !out) {
  console.error('uso: node sunra_gen.mjs <endpoint> <input.json> <salida>');
  process.exit(1);
}
const base = 'https://api.sunra.ai/v1/queue';
const input = JSON.parse(readFileSync(inputPath, 'utf8'));

async function call(url, init) {
  const res = await fetch(url, { ...init, headers: { 'Content-Type': 'application/json', ...(init?.headers ?? {}) } });
  const text = await res.text();
  let body;
  try { body = JSON.parse(text); } catch { body = text; }
  if (!res.ok) throw new Error(`${res.status} ${url}: ${typeof body === 'string' ? body : JSON.stringify(body)}`);
  return body;
}

const submitted = await call(`${base}/${endpoint}`, { method: 'POST', body: JSON.stringify(input) });
const id = submitted.request_id ?? submitted.id;
console.log('request', id);

let status;
for (let i = 0; i < 180; i++) {
  await new Promise((r) => setTimeout(r, 5000));
  status = await call(`${base}/requests/${id}/status`);
  const s = String(status.status ?? '').toUpperCase();
  if (i % 6 === 0) console.log('status', s);
  if (['COMPLETED', 'SUCCEEDED', 'SUCCESS'].includes(s)) break;
  if (['FAILED', 'ERROR', 'CANCELLED', 'CANCELED'].includes(s)) {
    throw new Error('falló: ' + JSON.stringify(status));
  }
}
const result = await call(`${base}/requests/${id}`);
writeFileSync(out + '.json', JSON.stringify(result, null, 2));
// Busca la primera URL de un archivo de video/audio en la respuesta.
const urls = JSON.stringify(result).match(/https?:\/\/[^"\\]+\.(mp4|mov|webm|mp3|wav|m4a)/g) ?? [];
if (!urls.length) throw new Error('sin URL de salida: ' + JSON.stringify(result).slice(0, 500));
const file = await fetch(urls[0]);
if (!file.ok) throw new Error(`descarga ${file.status} ${urls[0]}`);
writeFileSync(out, Buffer.from(await file.arrayBuffer()));
console.log('ok', out);

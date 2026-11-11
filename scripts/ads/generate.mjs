// Genera piezas publicitarias de Porty (imágenes y videos) con la API de Sunra.
// Los prompts viven en pieces.json; acá solo está la lógica.
//
// Uso (desde scripts/ads):
//   npm install
//   node generate.mjs all --dry              -> modelo, parámetros, prompts y costo, sin gastar
//   node generate.mjs feed-traductor         -> una pieza (se pueden pasar varias)
//   node generate.mjs images | videos | all  -> lotes
//   node generate.mjs fetch                  -> baja los videos que quedaron en cola
//   node generate.mjs refs                   -> solo renderiza las referencias de Porty
//   node generate.mjs ad01 ad02 --pieces ads.json --format feed --dry
//                                            -> otro catálogo (anuncios con formato feed/story)
//
// Flags: --model <endpoint>  --quality <low|medium|high>  --duration <s>
//        --pieces <archivo.json>  --format <feed|story>  --variants <n>
//        --no-wait (video: encola y sale)  --yes (lotes de más de ASK_ABOVE_CREDITS)
//
// La key sale de SUNRA_KEY (entorno o scripts/ads/.env, que git ignora).
// Nunca se escribe en logs ni en archivos.

import { createSunraClient } from "@sunra/client";
import { Resvg } from "@resvg/resvg-js";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { appendFile, mkdir, readFile, writeFile } from "node:fs/promises";
import { basename, dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, "..", "..");
const AVATAR_DIR = join(REPO, "assets/porty-avatar/states");
const OUT = join(HERE, "out");
const REFS_DIR = join(OUT, "refs");
const UPLOADS = join(OUT, "uploads.json");
const PENDING = join(OUT, "pending.json");

const DEFAULT_IMAGE_MODEL = "openai/gpt-image-2.5-flare/image-editing";
const DEFAULT_VIDEO_MODEL = "google/veo3-1-lite/image-to-video";
const ASK_ABOVE_CREDITS = 20;

// Tamaños finales para Instagram.
const EXPORT_SIZES = { "4:5": [1080, 1350], "9:16": [1080, 1920] };

// Referencias de Porty renderizadas desde los SVG del repo (el PNG del splash
// es de 256 px y limita la fidelidad). Fondo marfil liso.
const REFS = {
  "porty-idle": { svg: "porty_idle.svg", width: 2048, height: 2048, scale: 0.6 },
  "porty-thinking": { svg: "porty_thinking.svg", width: 2048, height: 2048, scale: 0.6 },
  // Primer cuadro de video vertical: Porty solo, un poco arriba del centro.
  "porty-idle-story": { svg: "porty_idle.svg", width: 1080, height: 1920, scale: 0.42, centerY: 0.46 },
  // Los cuatro estados a 1024 px, para los anuncios de ads.json.
  "ref-idle": { svg: "porty_idle.svg", width: 1024, height: 1024, scale: 0.75 },
  "ref-concerned": { svg: "porty_concerned.svg", width: 1024, height: 1024, scale: 0.75 },
  "ref-thinking": { svg: "porty_thinking.svg", width: 1024, height: 1024, scale: 0.75 },
  "ref-answered": { svg: "porty_answered.svg", width: 1024, height: 1024, scale: 0.75 },
};

// --- argumentos -------------------------------------------------------------

const VALUE_FLAGS = new Set(["model", "quality", "duration", "pieces", "format", "variants"]);
const flags = {};
const targets = [];
for (let i = 2; i < process.argv.length; i++) {
  const a = process.argv[i];
  if (!a.startsWith("--")) {
    targets.push(a);
    continue;
  }
  const name = a.slice(2);
  if (!VALUE_FLAGS.has(name)) {
    flags[name] = true;
    continue;
  }
  flags[name] = process.argv[++i];
  if (flags[name] === undefined) die(`Falta el valor de --${name}.`);
}

function die(msg) {
  console.error(msg);
  process.exit(1);
}

// --- modelos ----------------------------------------------------------------
// Cada adaptador traduce una pieza al input exacto del endpoint (verificado
// contra https://oapi.sunra.ai/main/<owner>/<model>/latest.json, 2026-10-29)
// y estima su costo en créditos (1 crédito = US$0,01, precios públicos de
// https://api.sunra.ai/v1/pricing/model/<id>/endpoint/<endpoint>).
// Un modelo sin adaptador no se manda: no adivinamos nombres de campos.

// gpt-image pide ancho y alto múltiplos de 16; estos dan la proporción exacta.
const GPT_SIZES = { "4:5": [1088, 1360], "9:16": [1152, 2048], "1:1": [1024, 1024] };
// Por tokens. Sunra publica 1024² high ≈ US$0,053 y low ≈ US$0,006, más
// ≈ US$0,01 por imagen de entrada; medium no tiene precio publicado.
const GPT_CREDITS_PER_MP = { low: [0.5, 1], medium: [1.5, 3], high: [5, 7] };

const veoRate = (model) => (model.includes("veo3-1-lite") ? 3 : model.includes("veo3-1-fast") ? 8 : null);
const seedanceRate = (model) => (model.includes("seedance-2.0-mini") ? 3.675 : model.includes("seedance-2.5") ? 10.7 : null);

const ADAPTERS = [
  {
    match: /^openai\/gpt-image-[^/]+\/(image-editing|text-to-image)$/,
    kind: "image",
    acceptsRefs: (m) => m.endsWith("/image-editing"),
    input: ({ prompt, piece, refUrls, quality }) => {
      const [width, height] = GPT_SIZES[piece.aspect_ratio] ?? die(`gpt-image: sin tamaño para ${piece.aspect_ratio}`);
      return {
        prompt,
        ...(refUrls.length ? { images: refUrls } : {}),
        width,
        height,
        quality: quality ?? "medium",
        output_format: "png",
      };
    },
    credits: ({ piece, quality, refCount }) => {
      const [w, h] = GPT_SIZES[piece.aspect_ratio] ?? [1024, 1024];
      const mp = (w * h) / 1024 ** 2;
      const [lo, hi] = GPT_CREDITS_PER_MP[quality ?? "medium"] ?? [5, 15];
      return [lo * mp + refCount * 0.8, hi * mp + refCount * 1.2];
    },
    freeze: 50,
  },
  {
    match: /^google\/gemini-nano-banana-[^/]+\/(image-editing|text-to-image)$/,
    kind: "image",
    acceptsRefs: (m) => m.endsWith("/image-editing"),
    input: ({ prompt, piece, refUrls }) => ({
      prompt,
      ...(refUrls.length ? { images: refUrls } : {}),
      aspect_ratio: piece.aspect_ratio,
      resolution: "2K",
    }),
    credits: () => [5, 5],
  },
  {
    match: /^ideogram\/ideogram-v4\.5\/text-to-image$/,
    kind: "image",
    acceptsRefs: () => false,
    input: ({ prompt, piece, quality }) => ({
      prompt,
      aspect_ratio: piece.aspect_ratio,
      resolution: "2K",
      quality: quality ?? "medium",
      number_of_images: 1,
      prompt_enhancer: false,
    }),
    credits: ({ quality }) => {
      const c = { low: 3, medium: 6, high: 22 }[quality ?? "medium"] ?? 22;
      return [c, c];
    },
    freeze: 22,
  },
  {
    match: /^black-forest-labs\/flux-kontext-pro\/reference-images-to-image$/,
    kind: "image",
    acceptsRefs: () => true,
    // Kontext no tiene 4:5; 3:4 es lo más cercano y se recorta al exportar.
    input: ({ prompt, piece, refUrls }) => ({
      prompt,
      reference_images: refUrls,
      aspect_ratio: piece.aspect_ratio === "4:5" ? "3:4" : piece.aspect_ratio,
      output_format: "png",
    }),
    credits: () => [4, 4],
  },
  {
    match: /^google\/veo3-1(-lite|-fast)?\/image-to-video$/,
    kind: "video",
    durations: [4, 6, 8],
    input: ({ prompt, negative, startUrl, duration }) => ({
      prompt,
      negative_prompt: negative,
      image: startUrl,
      aspect_ratio: "9:16",
      duration,
      resolution: "720p",
      generate_audio: false,
    }),
    credits: ({ model, duration }) => {
      const r = veoRate(model);
      return r ? [r * duration, r * duration] : null;
    },
  },
  {
    match: /^kling\/kling-v3-(pro|4k)\/image-to-video$/,
    kind: "video",
    durations: [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    // Sin aspect_ratio: sale con la proporción del primer cuadro.
    input: ({ prompt, negative, startUrl, duration }) => ({
      prompt,
      negative_prompt: negative,
      start_image_url: startUrl,
      duration: String(duration),
      generate_audio: false,
    }),
    credits: ({ model, duration }) => {
      const r = model.includes("v3-pro") ? 11.2 : 42;
      return [r * duration, r * duration];
    },
  },
  {
    match: /^bytedance\/seedance-(2\.0-mini|2\.5)\/image-to-video$/,
    kind: "video",
    durations: [4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
    input: ({ prompt, startUrl, duration }) => ({
      prompt,
      start_image: startUrl,
      duration,
      resolution: "720p",
      generate_audio: false,
    }),
    // Tokens = (24·s + 1)·ancho·alto / 1024, a US$/M según el modelo.
    credits: ({ model, duration }) => {
      const tokens = ((24 * duration + 1) * 720 * 1280) / 1024;
      const c = (tokens / 1e6) * seedanceRate(model) * 100;
      return [c, c];
    },
    freeze: 1800,
  },
];

function adapterFor(model, kind) {
  const a = ADAPTERS.find((x) => x.match.test(model));
  if (!a) {
    die(
      `No hay adaptador para "${model}". Verificá su schema en ` +
        `https://oapi.sunra.ai/main/<owner>/<model>/latest.json y agregalo a ADAPTERS.`,
    );
  }
  if (a.kind !== kind) die(`"${model}" es de ${a.kind}, no sirve para una pieza de ${kind}.`);
  return a;
}

// La duración más cercana que acepta el modelo (Veo solo hace 4, 6 u 8 s).
function fitDuration(adapter, wanted) {
  return adapter.durations.reduce((best, d) => (Math.abs(d - wanted) < Math.abs(best - wanted) ? d : best));
}

// --- piezas -----------------------------------------------------------------

const catalog = JSON.parse(await readFile(join(HERE, flags.pieces ?? "pieces.json"), "utf8"));
// Cada catálogo puede guardar sus resultados aparte (ads.json -> ads-out/ en la raíz).
const RESULTS = catalog.output_dir ? join(HERE, catalog.output_dir) : OUT;
const LOG = join(RESULTS, "log.jsonl");
const LOG_MD = join(RESULTS, "log.md");
const variants = Number(flags.variants ?? 1);

function buildImagePrompt(piece) {
  const usesPorty = (piece.refs ?? []).some((r) => r.startsWith("porty"));
  return [usesPorty ? catalog.porty : null, catalog.style, piece.prompt, piece.format_line]
    .filter(Boolean)
    .join("\n\n");
}

// En catálogos con formatos, la pieza toma la proporción y la línea de formato elegidas.
function withFormat(name, piece) {
  if (!catalog.formats) return { name, piece };
  const format = flags.format ?? "feed";
  const f = catalog.formats[format] ?? die(`Formato desconocido: "${format}". Opciones: ${Object.keys(catalog.formats).join(", ")}`);
  return { name: `${name}_${format}`, piece: { ...piece, format, aspect_ratio: f.aspect_ratio, format_line: f.line } };
}

function buildVideoPrompt(piece) {
  return `${catalog.video_style}\n\n${piece.prompt}`;
}

function resolveTargets() {
  const images = Object.keys(catalog.images);
  const videos = Object.keys(catalog.videos ?? {});
  const picked = [];
  for (const t of targets) {
    if (t === "all") picked.push(...images, ...videos);
    else if (t === "images") picked.push(...images);
    else if (t === "videos") picked.push(...videos);
    else if (catalog.images[t] || catalog.videos?.[t]) picked.push(t);
    else die(`Pieza desconocida: "${t}". Opciones: ${[...images, ...videos].join(", ")}`);
  }
  return [...new Set(picked)].map((name) =>
    catalog.images[name]
      ? { kind: "image", ...withFormat(name, catalog.images[name]) }
      : { name, kind: "video", piece: catalog.videos[name] },
  );
}

// --- archivos ---------------------------------------------------------------

async function readJson(file, fallback) {
  return existsSync(file) ? JSON.parse(await readFile(file, "utf8")) : fallback;
}

const writeJson = (file, value) => writeFile(file, JSON.stringify(value, null, 2) + "\n");

const log = (entry) => appendFile(LOG, JSON.stringify({ ts: new Date().toISOString(), ...entry }) + "\n");

// Resumen legible para revisar a mano; la columna de observaciones se completa al revisar.
async function logMarkdown({ file, model, input, cost, url, error }) {
  if (!catalog.output_dir) return;
  if (!existsSync(LOG_MD)) {
    await writeFile(
      LOG_MD,
      "# Log de generación\n\n| Fecha | Archivo | Modelo | Parámetros | Costo (US$) | URL | Observaciones |\n|---|---|---|---|---|---|---|\n",
    );
  }
  const { prompt, images, ...params } = input ?? {};
  if (images) params.referencias = images.length;
  const cells = [
    new Date().toISOString().slice(0, 16).replace("T", " "),
    file ? basename(file) : "—",
    model,
    `\`${JSON.stringify(params)}\``,
    cost ?? "—",
    url ?? "—",
    error ? `error: ${error}` : "",
  ];
  await appendFile(LOG_MD, `| ${cells.join(" | ")} |\n`);
}

const modelSlug = (model) => model.split("/")[1].replace(/^gemini-/, "");

// Nombre de salida: ad01_por_que_bajo_feed_nano-banana-2.1.png (con _2, _3… si ya existe).
function outputName(p, ext) {
  const base = p.piece.slug
    ? `${p.piece.slug}_${p.piece.format}_${modelSlug(p.model)}`
    : `${p.name}__${modelSlug(p.model)}__${stamp()}`;
  let file = join(RESULTS, `${base}.${ext}`);
  for (let i = 2; existsSync(file); i++) file = join(RESULTS, `${base}_${i}.${ext}`);
  return file;
}

const rel = (file) => relative(process.cwd(), file);

const stamp = () => new Date().toISOString().replace(/[-:]/g, "").replace("T", "-").slice(0, 15);

async function ensureRef(name) {
  const r = REFS[name] ?? die(`Referencia desconocida: "${name}". Opciones: ${Object.keys(REFS).join(", ")}`);
  const file = join(REFS_DIR, `${name}.png`);
  if (existsSync(file)) return file;
  const svg = await readFile(join(AVATAR_DIR, r.svg), "utf8");
  const viewBox = svg.match(/viewBox="([^"]+)"/)[1];
  const inner = svg.replace(/^<svg[^>]*>/, "").replace(/<\/svg>\s*$/, "");
  const size = Math.round(r.width * r.scale);
  const x = (r.width - size) / 2;
  const y = r.height * (r.centerY ?? 0.5) - size / 2;
  const page =
    `<svg xmlns="http://www.w3.org/2000/svg" width="${r.width}" height="${r.height}">` +
    `<rect width="100%" height="100%" fill="#FBFBFA"/>` +
    `<svg x="${x}" y="${y}" width="${size}" height="${size}" viewBox="${viewBox}">${inner}</svg></svg>`;
  await mkdir(REFS_DIR, { recursive: true });
  await writeFile(file, new Resvg(page).render().asPng());
  console.log(`  referencia renderizada: ${rel(file)}`);
  return file;
}

// Último archivo generado con éxito para una pieza (para usarlo de primer cuadro).
async function latestOutput(pieceName) {
  if (!existsSync(LOG)) return null;
  const lines = (await readFile(LOG, "utf8")).trim().split("\n");
  for (const line of lines.reverse()) {
    const e = JSON.parse(line);
    if (e.piece === pieceName && e.file && existsSync(join(HERE, e.file))) return join(HERE, e.file);
  }
  return null;
}

async function resolveStartFrame(spec) {
  const [type, name] = spec.split(":");
  if (type === "ref") return ensureRef(name);
  if (type === "piece") return latestOutput(name);
  die(`start_frame inválido: "${spec}" (usá ref:<nombre> o piece:<nombre>)`);
}

// Sube un archivo local una sola vez (cacheado por hash) y devuelve su URL pública.
async function uploadFile(sunra, file) {
  const bytes = await readFile(file);
  const hash = createHash("sha256").update(bytes).digest("hex");
  const cache = await readJson(UPLOADS, {});
  if (cache[hash]) return cache[hash].url;
  const url = await sunra.storage.upload(new File([bytes], basename(file), { type: "image/png" }));
  cache[hash] = { file: relative(HERE, file), url };
  await writeJson(UPLOADS, cache);
  return url;
}

async function download(url, file) {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`descarga ${res.status} de ${url}`);
  await writeFile(file, Buffer.from(await res.arrayBuffer()));
}

// Copia reescalada al tamaño de Instagram (con sips de macOS). Si la
// proporción no coincide, avisa en vez de deformar.
function exportForInstagram(file, aspect) {
  const size = EXPORT_SIZES[aspect];
  if (!size || process.platform !== "darwin") return null;
  const info = execFileSync("sips", ["-g", "pixelWidth", "-g", "pixelHeight", file]).toString();
  const w = Number(info.match(/pixelWidth: (\d+)/)[1]);
  const h = Number(info.match(/pixelHeight: (\d+)/)[1]);
  if (Math.abs(w / h - size[0] / size[1]) > 0.01) {
    console.warn(`  ojo: salió ${w}x${h}, no es ${aspect}; no la reescalo (recortala a mano)`);
    return null;
  }
  const target = file.replace(/\.png$/, `_${size[0]}x${size[1]}.png`);
  execFileSync("sips", ["--resampleHeightWidth", String(size[1]), String(size[0]), file, "--out", target], {
    stdio: "ignore",
  });
  return target;
}

// subscribe() y result() devuelven { data }; algunos endpoints anidan otra vez en data.
const unwrap = (data) => (data?.images || data?.video ? data : data?.data ?? data);

// --- plan (lo que se muestra en --dry y antes de gastar) ---------------------

async function plan(job) {
  const { kind, piece } = job;
  const model =
    flags.model ?? (kind === "image" ? catalog.default_image_model ?? DEFAULT_IMAGE_MODEL : DEFAULT_VIDEO_MODEL);
  const adapter = adapterFor(model, kind);
  const quality = flags.quality;
  if (kind === "image") {
    const refs = adapter.acceptsRefs(model) ? piece.refs ?? [] : [];
    const warn =
      (piece.refs ?? []).length && !refs.length
        ? "este modelo no acepta referencias: Porty va a salir deformado"
        : null;
    return {
      ...job,
      model,
      adapter,
      quality,
      refs,
      warn,
      prompt: buildImagePrompt(piece),
      credits: adapter.credits({ model, piece, quality, refCount: refs.length }).map((c) => c * variants),
    };
  }
  const wanted = Number(flags.duration ?? piece.duration);
  const duration = fitDuration(adapter, wanted);
  const startFrame = await resolveStartFrame(piece.start_frame);
  const warn = [
    duration !== wanted ? `pidió ${wanted} s, el modelo hace ${duration} s` : null,
    startFrame ? null : `falta el primer cuadro: generá antes ${piece.start_frame.split(":")[1]}`,
  ]
    .filter(Boolean)
    .join("; ");
  return {
    ...job,
    model,
    adapter,
    duration,
    startFrame,
    warn: warn || null,
    prompt: buildVideoPrompt(piece),
    credits: adapter.credits({ model, duration }),
  };
}

const fmtCredits = (c) =>
  !c ? "sin precio verificado" : Math.round(c[0]) === Math.round(c[1]) ? `~${Math.round(c[0])}` : `~${Math.round(c[0])}–${Math.round(c[1])}`;

function printPlan(p) {
  const placeholderRefs = (p.refs ?? []).map((r) => `<subida de out/refs/${r}.png>`);
  const input =
    p.kind === "image"
      ? p.adapter.input({ prompt: "…", piece: p.piece, refUrls: placeholderRefs, quality: p.quality })
      : p.adapter.input({
          prompt: "…",
          negative: "…",
          startUrl: p.startFrame ? `<subida de ${rel(p.startFrame)}>` : "<falta>",
          duration: p.duration,
        });
  console.log(`\n■ ${p.name}  (${p.kind}, ${p.piece.aspect_ratio ?? "9:16"}${variants > 1 ? `, ${variants} variantes` : ""})`);
  if (p.piece.idea) console.log(`  idea:     ${p.piece.idea}`);
  if (p.refs?.length) console.log(`  refs:     ${p.refs.map((r, i) => `${i + 1}=${r}`).join("  ")}`);
  console.log(`  modelo:   ${p.model}`);
  console.log(`  input:    ${JSON.stringify(input)}`);
  console.log(`  créditos: ${fmtCredits(p.credits)}${p.adapter.freeze ? ` (reserva ${p.adapter.freeze} al encolar)` : ""}`);
  if (p.piece.copy) console.log(`  copy:     ${p.piece.copy.map((c) => `«${c}»`).join("  ")}`);
  if (p.warn) console.log(`  ⚠ ${p.warn}`);
  console.log(`  prompt:\n${p.prompt.replace(/^/gm, "    ")}`);
}

// --- ejecución ---------------------------------------------------------------

async function runImage(sunra, p) {
  const refUrls = [];
  for (const r of p.refs) refUrls.push(await uploadFile(sunra, await ensureRef(r)));
  const input = p.adapter.input({ prompt: p.prompt, piece: p.piece, refUrls, quality: p.quality });
  const { data, requestId } = await sunra.subscribe(p.model, {
    input,
    onQueueUpdate: (u) => u.status === "IN_QUEUE" && u.position != null && console.log(`  en cola, posición ${u.position}`),
  });
  const out = unwrap(data);
  const url = out?.images?.[0]?.url;
  if (!url) throw new Error(`respuesta sin imagen: ${JSON.stringify(data).slice(0, 300)}`);
  const file = outputName(p, "png");
  await download(url, file);
  const exported = exportForInstagram(file, p.piece.aspect_ratio);
  await log({
    piece: p.name,
    model: p.model,
    request_id: requestId,
    input,
    output_url: url,
    file: relative(HERE, file),
    export: exported && relative(HERE, exported),
    units: out.units ?? null,
  });
  // Los modelos de precio fijo (Nano Banana) no informan units: se anota el precio de lista.
  const fixed = p.credits && p.credits[0] === p.credits[1] ? `${(p.credits[0] / variants / 100).toFixed(3)} (lista)` : null;
  await logMarkdown({ file, model: p.model, input, cost: out.units ?? fixed, url });
  console.log(`  listo: ${rel(exported ?? file)}${out.units != null ? `  (costo informado: ${out.units})` : ""}`);
}

async function finishVideo(sunra, job) {
  const { data } = await sunra.queue.result({ requestId: job.request_id });
  const out = unwrap(data);
  const url = out?.video?.url;
  if (!url) throw new Error(`respuesta sin video: ${JSON.stringify(data).slice(0, 300)}`);
  const file = join(RESULTS, `${job.piece}__${modelSlug(job.model)}__${stamp()}.mp4`);
  await download(url, file);
  await log({ ...job, output_url: url, file: relative(HERE, file), units: out.units ?? null });
  console.log(`  listo: ${rel(file)}`);
}

async function runVideo(sunra, p) {
  if (!p.startFrame) throw new Error(p.warn);
  const startUrl = await uploadFile(sunra, p.startFrame);
  const input = p.adapter.input({ prompt: p.prompt, negative: catalog.video_negative, startUrl, duration: p.duration });
  const { request_id } = await sunra.queue.submit(p.model, { input });
  const job = { piece: p.name, model: p.model, request_id, input, submitted: new Date().toISOString() };
  const pending = await readJson(PENDING, []);
  await writeJson(PENDING, [...pending, job]);
  console.log(`  encolado: ${request_id}`);
  if (flags["no-wait"]) return console.log("  bajalo después con: node generate.mjs fetch");
  await sunra.queue.subscribeToStatus({
    requestId: request_id,
    pollInterval: 5000,
    onQueueUpdate: (u) => console.log(`  ${u.status}${u.position != null ? `, posición ${u.position}` : ""}`),
  });
  await finishVideo(sunra, job);
  await writeJson(PENDING, (await readJson(PENDING, [])).filter((j) => j.request_id !== request_id));
}

async function fetchPending(sunra) {
  const pending = await readJson(PENDING, []);
  if (!pending.length) return console.log("No hay videos pendientes.");
  const left = [];
  for (const job of pending) {
    console.log(`→ ${job.piece} (${job.request_id})`);
    try {
      const { status } = await sunra.queue.status({ requestId: job.request_id });
      if (status !== "COMPLETED") {
        console.log(`  todavía ${status}`);
        left.push(job);
        continue;
      }
      await finishVideo(sunra, job);
    } catch (e) {
      console.error(`  error: ${errorText(e)}`);
      await log({ ...job, error: errorText(e) });
    }
  }
  await writeJson(PENDING, left);
}

const errorText = (e) => [e?.code, e?.message ?? String(e)].filter(Boolean).join(": ");

function client() {
  const envFile = join(HERE, ".env");
  if (!process.env.SUNRA_KEY && existsSync(envFile)) process.loadEnvFile(envFile);
  if (!process.env.SUNRA_KEY) {
    die(
      "Falta SUNRA_KEY. Exportala en la terminal (export SUNRA_KEY=...) o ponela en " +
        "scripts/ads/.env como SUNRA_KEY=... (ese archivo está en .gitignore).",
    );
  }
  return createSunraClient({ credentials: process.env.SUNRA_KEY });
}

// --- main ---------------------------------------------------------------------

if (!targets.length) {
  die(
    "Uso: node generate.mjs <pieza…|images|videos|all|fetch|refs> [--dry] [--model <id>] " +
      "[--quality <q>] [--duration <s>] [--no-wait] [--yes]",
  );
}

await mkdir(OUT, { recursive: true });
await mkdir(RESULTS, { recursive: true });

if (targets[0] === "refs") {
  for (const name of Object.keys(REFS)) console.log(rel(await ensureRef(name)));
  process.exit(0);
}

if (targets[0] === "fetch") {
  await fetchPending(client());
  process.exit(0);
}

const plans = [];
for (const job of resolveTargets()) plans.push(await plan(job));
const total = plans.reduce((acc, p) => (p.credits ? [acc[0] + p.credits[0], acc[1] + p.credits[1]] : acc), [0, 0]);
const unpriced = plans.filter((p) => !p.credits).length;

if (flags.dry) {
  for (const p of plans) printPlan(p);
  console.log(
    `\nTotal estimado: ${fmtCredits(total)} créditos (≈ US$${(total[1] / 100).toFixed(2)} como máximo)` +
      (unpriced ? `, más ${unpriced} pieza(s) sin precio verificado` : "") +
      ".\nCada llamada además reserva un monto al encolar; si el saldo no lo cubre, falla con INSUFFICIENT_CREDIT.",
  );
  process.exit(0);
}

if ((total[1] > ASK_ABOVE_CREDITS || unpriced) && !flags.yes) {
  die(
    `Este lote costaría ${fmtCredits(total)} créditos${unpriced ? " más piezas sin precio" : ""}. ` +
      `Revisalo con --dry y repetí con --yes para confirmar.`,
  );
}

const sunra = client();
for (const p of plans) {
  console.log(`→ ${p.name} con ${p.model} (${fmtCredits(p.credits)} créditos)`);
  if (p.warn) console.warn(`  ⚠ ${p.warn}`);
  try {
    if (p.kind === "image") {
      // Ningún endpoint de imagen soportado devuelve varias por pedido de forma uniforme: una llamada por variante.
      for (let v = 0; v < variants; v++) await runImage(sunra, p);
    } else await runVideo(sunra, p);
  } catch (e) {
    console.error(`  error en "${p.name}": ${errorText(e)}`);
    await log({ piece: p.name, model: p.model, error: errorText(e) });
    await logMarkdown({ model: p.model, error: errorText(e) });
  }
}

// Arma los anuncios de Porty con capturas reales de la app, sin IA: fondo
// marfil, lockup con el SVG oficial de Porty, titular en Plus Jakarta Sans
// con subrayado a mano y la captura dentro de un marco de celular.
// El copy vive en compose.json; acá solo está el layout.
//
// Uso (desde scripts/ads, después de generar las capturas con
// test/screenshots/ads_screenshots_test.dart):
//   node compose.mjs                 -> todos los anuncios, feed y story
//   node compose.mjs ad01 ad07       -> solo esos
//   node compose.mjs --format feed   -> un solo formato

import { Resvg } from "@resvg/resvg-js";
import { existsSync } from "node:fs";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import opentype from "opentype.js";

const HERE = dirname(fileURLToPath(import.meta.url));
const REPO = join(HERE, "..", "..");
const FONTS = join(REPO, "assets/fonts");
const AVATAR = join(REPO, "assets/porty-avatar/states");

const C = {
  bg: "#FBFBFA",
  card: "#FFFFFF",
  text: "#2F3437",
  secondary: "#787774",
  accent: "#D98E5D",
};

// Story: la interfaz de Instagram/TikTok tapa 250 px arriba y 340 abajo.
const FORMATS = {
  feed: { w: 1080, h: 1350, top: 64, headline: 84, sub: 34, phone: 600, gap: 64 },
  story: { w: 1080, h: 1920, top: 262, headline: 92, sub: 38, phone: 620, gap: 76 },
};

const LETTER_SPACING = -0.02; // em, titulares
const SIDE = 72; // margen lateral mínimo del texto

// Capturas de 1206x2622 (iPhone Pro a 3x); los primeros 141 px son el área
// de la barra de estado, que se dibuja encima.
const SHOT_W = 1206;
const STATUS_PX = 141;

const fonts = {
  bold: opentype.loadSync(join(FONTS, "PlusJakartaSans-Bold.ttf")),
  medium: opentype.loadSync(join(FONTS, "PlusJakartaSans-Medium.ttf")),
  regular: opentype.loadSync(join(FONTS, "PlusJakartaSans-Regular.ttf")),
};

// El texto se dibuja como trazos con opentype.js: resvg no aplica bien el
// kerning de la fuente (dejaba un hueco antes del punto). Mismas opciones
// para medir y para dibujar.
const textOptions = (spacing) => ({ kerning: true, letterSpacing: spacing });

const width = (font, text, size, spacing = 0) =>
  font.getAdvanceWidth(text, size, textOptions(spacing));

const textPath = (font, text, x, y, size, fill, spacing = 0) =>
  `<path d="${font.getPath(text, x, y, size, textOptions(spacing)).toPathData(2)}" fill="${fill}"/>`;

const esc = (s) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

// --- piezas del layout ---------------------------------------------------------

async function portySvg(state, x, y, size) {
  const svg = await readFile(join(AVATAR, `porty_${state}.svg`), "utf8");
  const viewBox = svg.match(/viewBox="([^"]+)"/)[1];
  const inner = svg.replace(/^<svg[^>]*>/, "").replace(/<\/svg>\s*$/, "");
  return `<svg x="${x}" y="${y}" width="${size}" height="${size}" viewBox="${viewBox}">${inner}</svg>`;
}

/// Porty + "Porty" centrados en [cy].
async function lockup(W, cy) {
  const size = 64;
  const fs = 40;
  const tw = width(fonts.bold, "Porty", fs, -0.02);
  const total = size + 12 + tw;
  const x = (W - total) / 2;
  return (
    (await portySvg("idle", x, cy - size / 2 - 2, size)) +
    textPath(fonts.bold, "Porty", x + size + 12, cy + fs * 0.36, fs, C.text, -0.02)
  );
}

/// Trazo a mano bajo [x1..x2]: apenas curvo y más grueso al centro.
function handUnderline(x1, x2, y, thick = 8) {
  const mid = (x1 + x2) / 2;
  return `<path d="M${x1} ${y + 3} Q${mid} ${y + 9} ${x2} ${y - 3}" fill="none" stroke="${C.accent}" stroke-width="${thick}" stroke-linecap="round"/>`;
}

/// Titular centrado, achicado si alguna línea no entra. Devuelve el SVG y
/// dónde terminó.
function headline(ad, W, top, baseSize) {
  const maxW = W - SIDE * 2;
  const widest = Math.max(...ad.lines.map((l) => width(fonts.bold, l, baseSize, LETTER_SPACING)));
  const fs = Math.min(baseSize, Math.floor((baseSize * maxW) / widest));
  const lh = fs * 1.08;
  let svg = "";
  let y = top + fs * 0.82;
  for (const line of ad.lines) {
    const lw = width(fonts.bold, line, fs, LETTER_SPACING);
    const x = (W - lw) / 2;
    svg += textPath(fonts.bold, line, x, y, fs, C.text, LETTER_SPACING);
    const at = ad.underline ? line.indexOf(ad.underline) : -1;
    if (at >= 0) {
      const x1 = x + width(fonts.bold, line.slice(0, at), fs, LETTER_SPACING);
      const x2 = x1 + width(fonts.bold, ad.underline, fs, LETTER_SPACING) - LETTER_SPACING * fs;
      svg += handUnderline(x1 + 4, x2 - 4, y + fs * 0.2, Math.max(6, fs * 0.09));
    }
    y += lh;
  }
  return { svg, bottom: y - lh + fs * 0.3 };
}

function subline(text, W, top, fs) {
  const lw = width(fonts.regular, text, fs);
  const y = top + fs;
  return {
    svg: textPath(fonts.regular, text, (W - lw) / 2, y, fs, C.secondary),
    bottom: y + fs * 0.3,
  };
}

/// Celular con la captura, centrado, cortado por el borde inferior.
async function phone(file, W, top, phoneW, offset = 0) {
  const bezel = Math.round(phoneW * 0.026);
  const screenW = phoneW - bezel * 2;
  const scale = screenW / SHOT_W;
  const radius = phoneW * 0.13;
  const x = (W - phoneW) / 2;
  const sx = x + bezel;
  const sy = top + bezel;
  const screenH = 2622 * scale;
  const statusH = STATUS_PX * scale;
  const png = (await readFile(file)).toString("base64");
  const href = `data:image/png;base64,${png}`;
  const id = `s${Math.random().toString(36).slice(2, 8)}`;
  // Isla y hora: la barra de estado de un iPhone, sin íconos de más.
  const island = `<rect x="${x + phoneW / 2 - screenW * 0.16}" y="${sy + statusH * 0.24}" width="${screenW * 0.32}" height="${statusH * 0.5}" rx="${statusH * 0.25}" fill="#111"/>`;
  const clock = `<text x="${sx + screenW * 0.13}" y="${sy + statusH * 0.62}" font-family="Plus Jakarta Sans" font-weight="600" font-size="${statusH * 0.36}" fill="${C.text}">9:41</text>`;
  return `
    <defs>
      <clipPath id="${id}"><rect x="${sx}" y="${sy}" width="${screenW}" height="${screenH}" rx="${radius - bezel}"/></clipPath>
      <clipPath id="${id}b"><rect x="${sx}" y="${sy + statusH}" width="${screenW}" height="${screenH}"/></clipPath>
    </defs>
    <rect x="${x}" y="${top}" width="${phoneW}" height="${screenH + bezel * 2}" rx="${radius}" fill="${C.text}"/>
    <g clip-path="url(#${id})">
      <image href="${href}" x="${sx}" y="${sy}" width="${screenW}" height="${screenH}"/>
      ${offset ? `<g clip-path="url(#${id}b)"><image href="${href}" x="${sx}" y="${sy - offset * scale}" width="${screenW}" height="${screenH}"/></g>` : ""}
    </g>
    ${island}${clock}`;
}

/// En el margen izquierdo, al lado del celular (nunca encima).
function caption(text, W, H, bottomSafe) {
  const fs = 22;
  return `<text x="28" y="${H - bottomSafe - 28}" font-family="Plus Jakarta Sans" font-weight="500" font-size="${fs}" fill="${C.secondary}">${esc(text)}</text>`;
}

/// "No te dice qué comprar": sin celular, con el sticker tachado y Porty grande.
async function statement(ad, f, W, H, y, bottomSafe) {
  const fs = f.sub;
  let svg = "";
  const stickerFs = Math.round(f.headline * 0.62);
  const sw = width(fonts.medium, ad.sticker, stickerFs) + stickerFs * 1.4;
  const sh = stickerFs * 1.9;
  const cy = y + (H - y) * 0.2;
  svg += `<g transform="rotate(-6 ${W / 2} ${cy})">
    <rect x="${(W - sw) / 2}" y="${cy - sh / 2}" width="${sw}" height="${sh}" rx="${sh / 2}" fill="${C.card}" stroke="#00000014" stroke-width="2"/>
    <text x="${W / 2}" y="${cy + stickerFs * 0.35}" text-anchor="middle" font-family="Plus Jakarta Sans" font-weight="500" font-size="${stickerFs}" fill="${C.secondary}">${esc(ad.sticker)}</text>
    <path d="M${(W - sw) / 2 + 24} ${cy + 6} Q${W / 2} ${cy - 4} ${(W + sw) / 2 - 24} ${cy - 10}" fill="none" stroke="${C.accent}" stroke-width="${fs * 0.24}" stroke-linecap="round"/>
  </g>`;
  // Grande y cortado por abajo, con la cara entera a la vista.
  const size = W * 0.56;
  svg += await portySvg("idle", (W - size) / 2, H - bottomSafe - size * 0.8, size);
  return svg;
}

async function compose(ad, format, screensDir) {
  const f = FORMATS[format];
  const { w: W, h: H } = f;
  const bottomSafe = format === "story" ? 340 : 0;
  let body = await lockup(W, f.top + 32);
  const head = headline(ad, W, f.top + 32 + 70, f.headline);
  body += head.svg;
  const sub = subline(ad.sub, W, head.bottom + 22, f.sub);
  body += sub.svg;
  if (ad.kind === "statement") {
    body += await statement(ad, f, W, H, sub.bottom, bottomSafe);
  } else {
    const file = join(screensDir, ad.screen);
    if (!existsSync(file)) throw new Error(`falta la captura ${ad.screen}: corré el test de screenshots`);
    body += await phone(file, W, sub.bottom + f.gap, f.phone, ad.offset ?? 0);
    body += caption("Ejemplo ilustrativo", W, H, bottomSafe);
  }
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="${W}" height="${H}" viewBox="0 0 ${W} ${H}">
    <rect width="${W}" height="${H}" fill="${C.bg}"/>${body}</svg>`;
  return new Resvg(svg, {
    font: {
      fontFiles: ["Regular", "Medium", "SemiBold", "Bold"].map((w) => join(FONTS, `PlusJakartaSans-${w}.ttf`)),
      loadSystemFonts: false,
      defaultFontFamily: "Plus Jakarta Sans",
    },
  })
    .render()
    .asPng();
}

// --- main ------------------------------------------------------------------------

const argv = process.argv.slice(2);
const fi = argv.indexOf("--format");
const formats = fi >= 0 ? [argv[fi + 1]] : Object.keys(FORMATS);
const wanted = argv.filter((a, i) => !a.startsWith("--") && argv[i - 1] !== "--format");

const config = JSON.parse(await readFile(join(HERE, "compose.json"), "utf8"));
const screensDir = join(HERE, config.screens_dir);
const outDir = join(HERE, config.output_dir);
await mkdir(outDir, { recursive: true });

for (const [key, ad] of Object.entries(config.ads)) {
  if (wanted.length && !wanted.includes(key)) continue;
  for (const format of formats) {
    if (!FORMATS[format]) throw new Error(`formato desconocido: ${format}`);
    try {
      const png = await compose(ad, format, screensDir);
      const file = join(outDir, `${ad.slug}_${format}.png`);
      await writeFile(file, png);
      console.log(`listo: ${file.replace(REPO + "/", "")}`);
    } catch (e) {
      console.error(`error en ${key} (${format}): ${e.message}`);
    }
  }
}

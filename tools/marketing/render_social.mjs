// Genera las piezas de redes de la semana de presentación (PR1, PR2, PR3, PR5)
// con plantillas de marca (DESIGN.md) y capturas reales de la app.
//
// Uso (desde la raíz del repo):
//   node tools/marketing/render_social.mjs <carpeta_capturas> <carpeta_salida>
// <carpeta_capturas> sale de los screenshot tests:
//   RUN_SCREENSHOTS=1 SCREENSHOTS_OUT=<carpeta_capturas>/genui_catalog \
//     flutter test test/screenshots/genui_catalog_screenshots_test.dart
// Textos: docs/marketing/social/2026-11-03-plan-lanzamiento-ig-tiktok.md con las
// correcciones de docs/legal/reviews/2026-11-03-plan-redes.md (§2 y §6).
// El video PR1 se arma después con tools/marketing/render_pr1.sh.
import { createRequire } from 'node:module';
import { readFileSync, mkdirSync } from 'node:fs';
import path from 'node:path';

// Playwright puede estar instalado global (fuera de un package.json): require lo encuentra.
const { chromium } = createRequire(import.meta.url)('playwright');

const [shotsDir, outDir] = process.argv.slice(2);
if (!shotsDir || !outDir) {
  console.error('uso: node tools/marketing/render_social.mjs <capturas> <salida>');
  process.exit(1);
}
mkdirSync(outDir, { recursive: true });

const b64 = (p) => readFileSync(p).toString('base64');
const font = (w) => b64(`assets/fonts/PlusJakartaSans-${w}.ttf`);
const svg = (name) => `data:image/svg+xml;base64,${b64(`assets/porty-avatar/states/${name}.svg`)}`;
const png = (rel) => `data:image/png;base64,${b64(path.join(shotsDir, rel))}`;

// Disclaimers aprobados (review §2). Por decisión del usuario no van en las
// imágenes: van en el caption de cada pieza (ver el plan). Se dejan acá por si
// hace falta volver a ponerlos (opción foot de page()).
const D = {
  A: 'Cuenta demo. No es asesoramiento financiero.',
  B: 'Cuenta demo. Rendimientos pasados no garantizan resultados futuros. No es asesoramiento financiero.',
  C: 'Porty usa IA y puede equivocarse. Verificá la información importante.',
  D: 'Algunas funciones son de planes pagos.',
  NA: 'No es asesoramiento financiero.',
};

const SHOT_PORTFOLIO = png('genui_catalog/QaPositionsSnapshot_0_light.png');
const SHOT_EXPLAIN = png('genui_catalog/QaConcentrationBar_0_light.png');

const css = `
@font-face{font-family:PJS;font-weight:400;src:url(data:font/ttf;base64,${font('Regular')})}
@font-face{font-family:PJS;font-weight:500;src:url(data:font/ttf;base64,${font('Medium')})}
@font-face{font-family:PJS;font-weight:600;src:url(data:font/ttf;base64,${font('SemiBold')})}
@font-face{font-family:PJS;font-weight:700;src:url(data:font/ttf;base64,${font('Bold')})}
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:PJS;background:#FBFBFA;color:#2F3437;font-feature-settings:"tnum"}
.frame{position:relative;width:1080px;display:flex;flex-direction:column;padding:96px 88px;overflow:hidden}
.content{flex:1;min-height:0;display:flex;flex-direction:column}
.brand{display:flex;align-items:center;gap:18px;font-weight:700;font-size:34px;letter-spacing:-0.5px}
.brand img{width:56px;height:56px}
.pill{position:absolute;top:104px;right:88px;font-size:26px;font-weight:600;color:#787774;
  border:1px solid #E6E4E0;background:#fff;border-radius:999px;padding:10px 22px}
.kicker{font-size:30px;font-weight:600;color:#D98E5D;margin-top:72px}
h1{font-size:68px;line-height:1.08;font-weight:700;letter-spacing:-1.5px;margin-top:20px}
.sub{font-size:40px;line-height:1.35;color:#787774;margin-top:28px;font-weight:500}
.shot{margin:40px auto 0;max-width:100%;object-fit:contain;display:block}
.tag{display:inline-block;margin-top:24px;font-size:26px;font-weight:600;color:#787774}
.avatar{display:block;margin:0 auto 24px}
.foot{font-size:28px;line-height:1.4;color:#5E5D5A;margin-top:32px}
.page{position:absolute;right:88px;top:112px;font-size:28px;color:#9B9A97;font-weight:600}
.note{font-size:30px;color:#9B9A97;margin-top:18px;line-height:1.4}
`;

// Pie: en stories queda fuera de los 340 px de abajo (zona de botones/link).
function page({ h, kicker, title, sub, note, shot, tag, avatar, avatarSize = 360, foot, pill, num, center }) {
  const padBottom = h === 1920 ? 360 : 80; // stories: fuera de los 340 px de abajo
  const shotMax = h === 1920 ? 820 : 480;
  return `<!doctype html><html><head><meta charset="utf-8"><style>${css}</style></head><body>
<div class="frame" style="height:${h}px;padding-bottom:${padBottom}px">
  <div class="brand"><img src="${svg('porty_idle')}">Porty</div>
  ${pill ? `<div class="pill" style="right:${num ? 170 : 88}px">${pill}</div>` : ''}
  ${num ? `<div class="page">${num}</div>` : ''}
  <div class="content" style="${center ? 'justify-content:center;' : ''}">
    ${avatar ? `<img class="avatar" src="${svg(avatar)}" style="width:${avatarSize}px;margin-top:${center ? 0 : 64}px">` : ''}
    ${kicker ? `<div class="kicker">${kicker}</div>` : ''}
    ${title ? `<h1 style="${center ? 'text-align:center;' : ''}">${title}</h1>` : ''}
    ${sub ? `<div class="sub" style="${center ? 'text-align:center;' : ''}">${sub}</div>` : ''}
    ${note ? `<div class="note" style="${center ? 'text-align:center;' : ''}">${note}</div>` : ''}
    ${shot ? `<img class="shot" src="${shot}" style="max-height:${shotMax}px">` : ''}
    ${tag ? `<div class="tag">${tag}</div>` : ''}
  </div>
  ${foot ? `<div class="foot">${foot}</div>` : ''}
</div></body></html>`;
}

const FEED = 1350;
const STORY = 1920;

const pieces = {
  // PR3. Conocé a Porty (feed + story). Review §6: "asistente para entender tu cartera".
  'PR3_conoce_a_porty_feed': page({ h: FEED, center: true, avatar: 'porty_idle', avatarSize: 420,
    title: 'Conocé a Porty.', sub: 'Tu asistente para entender tu cartera. Te la explica con calma.' }),
  'PR3_conoce_a_porty_story': page({ h: STORY, center: true, avatar: 'porty_idle', avatarSize: 520,
    title: 'Conocé a Porty.', sub: 'Tu asistente para entender tu cartera. Te la explica con calma.' }),

  // PR2. Qué es Porty en 5 placas (carrusel 1080x1350).
  'PR2_placa1': page({ h: FEED, num: '1/5', avatar: 'porty_idle', avatarSize: 260,
    kicker: 'Qué es Porty, en cinco placas', title: 'Una app para ver tu cartera y un asistente que te la explica.' }),
  'PR2_placa2': page({ h: FEED, num: '2/5', kicker: 'Para quién',
    title: 'Para quien invierte sin vivir pegado al mercado.' }),
  'PR2_placa3': page({ h: FEED, num: '3/5', kicker: 'Qué problema resuelve',
    title: 'Mirar solo el total no alcanza para entender cómo viene tu cartera.', shot: SHOT_PORTFOLIO }),
  'PR2_placa4': page({ h: FEED, num: '4/5', kicker: 'Cómo se usa',
    title: 'Cargás tu cartera, la mirás de un vistazo, le preguntás a Porty.', shot: SHOT_EXPLAIN }),
  'PR2_placa5': page({ h: FEED, num: '5/5', center: true, avatar: 'porty_answered', avatarSize: 320,
    title: 'Descargala gratis.', sub: 'Algunas funciones son de planes pagos.' }),

  // PR5. Stories de presentación (stickers se agregan en Instagram, hay aire reservado).
  'PR5_story1': page({ h: STORY, center: true, avatar: 'porty_idle', avatarSize: 480,
    title: 'Hola, soy Porty.', sub: 'Un asistente con IA. Te ayudo a entender tu cartera.' }),
  'PR5_story2': page({ h: STORY, kicker: 'Para quién',
    title: 'Si tu plata está repartida en varias apps, Porty te ayuda a verla junta.',
    note: 'Conectando brókers en planes pagos, o con un import.' }),
  'PR5_story3': page({ h: STORY, kicker: 'Qué hace',
    title: 'Tu cartera en un solo lugar.', shot: SHOT_PORTFOLIO }),
  'PR5_story4': page({ h: STORY, kicker: 'Cómo se usa',
    title: 'Cargás tu cartera, la entendés de un vistazo, le preguntás a Porty.', shot: SHOT_EXPLAIN }),
  'PR5_story5': page({ h: STORY, center: true, avatar: 'porty_answered', avatarSize: 440,
    title: 'Descargala gratis.', sub: 'Link abajo.' }),

  // PR1. Escenas del video manifiesto (9:16). El pie B+C+D va en la última (≥ 3 s).
  'PR1_s1_hook': page({ h: STORY, center: true, avatar: 'porty_idle', avatarSize: 220,
    title: '¿Tu cartera te cuenta lo que pasa?' }),
  'PR1_s2_esto_es_porty': page({ h: STORY, center: true, avatar: 'porty_idle', avatarSize: 420,
    title: 'Esto es Porty.', sub: 'Tu cartera en un solo lugar.' }),
  'PR1_s3_para_quien': page({ h: STORY, kicker: 'Para quién',
    title: 'Para quien invierte sin vivir pegado al mercado.', shot: SHOT_PORTFOLIO }),
  'PR1_s4_te_explica': page({ h: STORY, kicker: 'Cómo se usa',
    title: 'Le preguntás a Porty y te explica tus números en tu idioma.', shot: SHOT_EXPLAIN }),
  'PR1_s5_cierre': page({ h: STORY, center: true, avatar: 'porty_answered', avatarSize: 420,
    title: 'Descargala gratis.', sub: 'Porty. Tu asistente para entender tu cartera.' }),
};

const browser = await chromium.launch();
const pg = await browser.newPage({ viewport: { width: 1080, height: 1920 } });
for (const [name, html] of Object.entries(pieces)) {
  const h = name.includes('feed') || name.startsWith('PR2') ? FEED : STORY;
  await pg.setViewportSize({ width: 1080, height: h });
  await pg.setContent(html, { waitUntil: 'load' });
  await pg.evaluate(() => document.fonts.ready);
  await pg.screenshot({ path: path.join(outDir, `${name}.png`) });
  console.log(name);
}
await browser.close();

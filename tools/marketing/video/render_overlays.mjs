// Titulares para los planos live action (PNG transparente 1080x1920, tipografía
// de la marca). Uso: node tools/marketing/video/render_overlays.mjs <salida_dir>
import { createRequire } from 'node:module';
import { readFileSync, mkdirSync } from 'node:fs';
import path from 'node:path';

const { chromium } = createRequire(import.meta.url)('playwright');
const outDir = process.argv[2];
mkdirSync(outDir, { recursive: true });
const font = (w) => readFileSync(`assets/fonts/PlusJakartaSans-${w}.ttf`).toString('base64');

const lines = {
  ov_plata: 'Tu plata está en <span>varios lados.</span>',
  ov_juntala: 'Juntala en <span>Porty.</span>',
};

const html = (text) => `<!doctype html><html><head><meta charset="utf-8"><style>
@font-face{font-family:PJS;font-weight:700;src:url(data:font/ttf;base64,${font('Bold')})}
html,body{margin:0;width:1080px;height:1920px;background:transparent}
.scrim{position:absolute;left:0;right:0;top:0;height:760px;
  background:linear-gradient(to bottom,rgba(20,16,12,.55),rgba(20,16,12,0))}
h1{position:absolute;left:90px;right:90px;top:250px;margin:0;font-family:PJS;font-weight:700;
  font-size:92px;line-height:1.04;letter-spacing:-2.2px;color:#FFFFFF;
  text-shadow:0 4px 30px rgba(0,0,0,.25)}
h1 span{color:#F2B48C}
</style></head><body><div class="scrim"></div><h1>${text}</h1></body></html>`;

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1080, height: 1920 } });
for (const [name, text] of Object.entries(lines)) {
  await page.setContent(html(text));
  await page.evaluate(() => document.fonts.ready);
  await page.screenshot({ path: path.join(outDir, `${name}.png`), omitBackground: true });
}
await browser.close();

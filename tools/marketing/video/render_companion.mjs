// Renderiza a Porty personaje (porty_companion.html) por escena, con fondo
// transparente, en un .mov con canal alfa (PNG) para superponer en ffmpeg.
// Uso: node tools/marketing/video/render_companion.mjs <salida_dir> [escena:duración ...]
import { createRequire } from 'node:module';
import { spawn } from 'node:child_process';
import path from 'node:path';

const { chromium } = createRequire(import.meta.url)('playwright');
const [outDir, ...specs] = process.argv.slice(2);
const scenes = (specs.length ? specs : ['cocina:3.2', 'colectivo:2.6', 'sillon:3.0', 'pulgar:2.0'])
  .map((s) => s.split(':')).map(([name, d]) => ({ name, dur: Number(d) }));
const fps = 30;

const browser = await chromium.launch({ args: ['--allow-file-access-from-files'] });
const page = await browser.newPage({ viewport: { width: 1080, height: 1920 } });
await page.goto('file://' + path.resolve('tools/marketing/video/porty_companion.html'));
await page.evaluate(() => document.fonts.ready);

for (const { name, dur } of scenes) {
  const out = path.join(outDir, `porty_${name}.mov`);
  const ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(fps),
    '-c:v', 'png', '-i', '-', '-c:v', 'png', '-pix_fmt', 'rgba', out], { stdio: ['pipe', 'inherit', 'inherit'] });
  const frames = Math.round(dur * fps);
  for (let f = 0; f < frames; f++) {
    await page.evaluate(([n, t]) => window.render(n, t), [name, f / fps]);
    const buf = await page.screenshot({ type: 'png', omitBackground: true });
    if (!ff.stdin.write(buf)) await new Promise((r) => ff.stdin.once('drain', r));
  }
  ff.stdin.end();
  await new Promise((r) => ff.on('close', r));
  console.log(out);
}
await browser.close();

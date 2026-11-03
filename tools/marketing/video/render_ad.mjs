// Renderiza tools/marketing/video/porty_ad.html cuadro por cuadro y lo codifica
// en MP4 (H.264, 1080x1920).
//
// Uso (desde la raíz del repo):
//   node tools/marketing/video/render_ad.mjs <salida.mp4> [fps=60] [audio.m4a]
// Si se pasa un audio (locución + música), se mezcla; si no, el video va con
// una pista muda.
import { createRequire } from 'node:module';
import { spawn } from 'node:child_process';
import path from 'node:path';

const { chromium } = createRequire(import.meta.url)('playwright');
const [out, fpsArg, audio] = process.argv.slice(2);
if (!out) {
  console.error('uso: node tools/marketing/video/render_ad.mjs <salida.mp4> [fps] [audio]');
  process.exit(1);
}
const fps = Number(fpsArg ?? 60);

const browser = await chromium.launch({ args: ['--allow-file-access-from-files'] });
const page = await browser.newPage({ viewport: { width: 1080, height: 1920 } });
await page.goto('file://' + path.resolve(process.env.AD_HTML ?? 'tools/marketing/video/porty_ad.html'));
await page.evaluate(() => document.fonts.ready);
// Precarga las dos caras del avatar del chat para que el cambio no parpadee.
await page.evaluate(async () => {
  for (const s of ['porty_thinking', 'porty_answered']) {
    const i = new Image();
    i.src = `../../../assets/porty-avatar/states/${s}.svg`;
    await i.decode();
  }
});
const duration = await page.evaluate(() => window.DURATION);
const frames = Math.round(duration * fps);

const audioArgs = audio
  ? ['-i', audio, '-map', '0:v', '-map', '1:a', '-c:a', 'aac', '-b:a', '192k', '-shortest']
  : ['-f', 'lavfi', '-i', 'anullsrc=r=48000:cl=stereo', '-map', '0:v', '-map', '1:a', '-c:a', 'aac', '-shortest'];
const ff = spawn('ffmpeg', [
  '-y', '-loglevel', 'error',
  '-f', 'image2pipe', '-framerate', String(fps), '-c:v', 'mjpeg', '-i', '-',
  ...audioArgs,
  '-c:v', 'libx264', '-preset', 'slow', '-crf', '17', '-pix_fmt', 'yuv420p',
  '-r', String(fps), '-movflags', '+faststart', out,
], { stdio: ['pipe', 'inherit', 'inherit'] });

for (let f = 0; f < frames; f++) {
  await page.evaluate((t) => window.render(t), f / fps);
  const buf = await page.screenshot({ type: 'jpeg', quality: 95 });
  if (!ff.stdin.write(buf)) await new Promise((r) => ff.stdin.once('drain', r));
  if (f % fps === 0) process.stdout.write(`${f / fps}s `);
}
ff.stdin.end();
await new Promise((r) => ff.on('close', r));
await browser.close();
console.log('\n' + out);

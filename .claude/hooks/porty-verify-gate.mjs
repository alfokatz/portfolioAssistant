#!/usr/bin/env node
// Compuerta de verificación de Porty (hook Stop).
// Cuando Claude termina un turno con cambios de código sin commitear (lib/,
// test/, supabase/, tools/verify/) y en la sesión no corrió ninguna
// verificación (verify.sh, e2e, flutter test, deno test, tests SQL):
//   - off:     no hace nada.
//   - observe: (por defecto) lo anota en .claude/verify-gate.log y deja seguir.
//   - enforce: le pide a Claude que verifique antes de terminar (exit 2). Si ya
//              lo pidió una vez en este turno (stop_hook_active), deja pasar
//              para que Claude no quede trabado.
// El modo sale de PORTY_VERIFY_GATE (env en .claude/settings.json).
// Si el hook mismo falla, deja pasar (exit 0).
import { execFileSync } from 'node:child_process';
import { appendFileSync, readFileSync, existsSync } from 'node:fs';
import path from 'node:path';

const MODE = (process.env.PORTY_VERIFY_GATE || 'observe').toLowerCase();
const CODE_PATHS = /^(lib|test|supabase|tools\/verify|integration_test)\//;
const VERIFY_EVIDENCE = [
  'tools/verify/verify.sh',
  'tools/verify/e2e/run.sh',
  'tools/verify/sql-tests.sh',
  'flutter test',
  'deno test',
  'porty-test-runner',
];

let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => (raw += c));
process.stdin.on('end', () => {
  try {
    if (MODE === 'off') process.exit(0);
    const input = JSON.parse(raw || '{}');
    const projectDir = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();

    const status = execFileSync('git', ['status', '--porcelain'], { cwd: projectDir, encoding: 'utf8' });
    const changed = status
      .split('\n')
      .map((l) => l.slice(3).trim())
      .filter((f) => f && CODE_PATHS.test(f));
    if (changed.length === 0) process.exit(0);

    const transcript =
      input.transcript_path && existsSync(input.transcript_path)
        ? readFileSync(input.transcript_path, 'utf8')
        : '';
    const verified = VERIFY_EVIDENCE.some((e) => transcript.includes(e));
    if (verified) process.exit(0);

    const entry = {
      at: new Date().toISOString(),
      mode: MODE,
      session: input.session_id,
      wouldBlock: true,
      files: changed.slice(0, 20),
    };
    appendFileSync(path.join(projectDir, '.claude', 'verify-gate.log'), JSON.stringify(entry) + '\n');

    if (MODE === 'enforce' && !input.stop_hook_active) {
      process.stderr.write(
        'porty-verify-gate: hay cambios de código sin verificar en esta sesión ' +
          `(${changed.slice(0, 5).join(', ')}${changed.length > 5 ? ', …' : ''}). ` +
          'Corré tools/verify/verify.sh (skill porty-verify) antes de terminar, ' +
          'o explicá en tu respuesta por qué no se puede verificar.\n',
      );
      process.exit(2);
    }
    process.exit(0);
  } catch {
    process.exit(0);
  }
});

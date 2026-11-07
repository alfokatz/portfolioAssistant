#!/usr/bin/env node
// Guardrails de Porty para Claude Code (PreToolUse).
// Bloquea (exit 2) acciones que las reglas del repo prohíben sin excepciones:
//  1. Editar una migración ya commiteada en supabase/migrations/ (siempre va una nueva).
//  2. `git stash` (hay un stash viejo que un pop aplicaría).
//  3. `dart format` sobre carpetas (solo archivos .dart sueltos).
// Si el hook mismo falla, deja pasar (exit 0): no es un mecanismo de seguridad.
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import path from 'node:path';

function block(reason) {
  process.stderr.write(`porty-guard: ${reason}\n`);
  process.exit(2);
}

let raw = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', (c) => (raw += c));
process.stdin.on('end', () => {
  let input;
  try {
    input = JSON.parse(raw);
  } catch {
    process.exit(0);
  }
  const tool = input.tool_name ?? '';
  const args = input.tool_input ?? {};
  const projectDir = process.env.CLAUDE_PROJECT_DIR || input.cwd || process.cwd();

  if (['Edit', 'Write', 'MultiEdit', 'NotebookEdit'].includes(tool)) {
    const filePath = args.file_path ?? args.notebook_path;
    if (!filePath) process.exit(0);
    const abs = path.resolve(projectDir, filePath);
    const rel = path.relative(projectDir, abs).split(path.sep).join('/');
    if (rel.startsWith('supabase/migrations/') && existsSync(abs)) {
      let tracked = false;
      try {
        execFileSync('git', ['ls-files', '--error-unmatch', rel], {
          cwd: projectDir,
          stdio: 'ignore',
        });
        tracked = true;
      } catch {
        tracked = false;
      }
      if (tracked) {
        block(
          `${rel} ya está commiteada. Nunca se edita una migración existente ` +
            '(el usuario hace db push sin avisar): creá una migración nueva e idempotente.',
        );
      }
    }
    process.exit(0);
  }

  if (tool === 'Bash') {
    // Se ignora el texto entre comillas (mensajes de commit, greps, echos) para
    // no bloquear comandos que solo mencionan las palabras prohibidas.
    const cmd = String(args.command ?? '')
      .replace(/'[^']*'/g, "''")
      .replace(/"(?:[^"\\]|\\.)*"/g, '""');
    if (/(^|[\s;&|(])git\s+((-C|-c)\s+\S+\s+|-\S+\s+)*stash\b/.test(cmd)) {
      block(
        'git stash está prohibido en este repo (hay un stash viejo). ' +
          'Para comparar contra el original copiá archivos al scratchpad o usá git worktree.',
      );
    }
    for (const m of cmd.matchAll(/(?:^|[\s;&|(])dart\s+format\b([^;&|\n]*)/g)) {
      const targets = m[1]
        .trim()
        .split(/\s+/)
        .filter((t) => t && !t.startsWith('-'));
      const bad = targets.length === 0 || targets.some((t) => !t.endsWith('.dart'));
      if (bad) {
        block(
          'dart format solo sobre archivos .dart que creaste o tocaste, listados uno por uno ' +
            '(nunca carpetas como lib/ o test/).',
        );
      }
    }
  }
  process.exit(0);
});

#!/usr/bin/env node
/**
 * Nothing in components/ may contain a colour, font size or spacing literal: every such value comes
 * from the generated Theme. Component XML declares structure and interface fields only; component
 * BrighterScript may use the small integers that are not design values (0, 1, 2 as indices, halves
 * and counts; 100 and 1000 for percent and millisecond conversion).
 */
import {readFileSync, readdirSync, statSync} from 'node:fs';
import {dirname, join, relative} from 'node:path';
import {fileURLToPath} from 'node:url';

const app = join(dirname(fileURLToPath(import.meta.url)), '..');
const allowed = new Set(['0', '1', '2', '100', '1000', '0.5', '1.0', '0.0']);
const layoutAttributes = /\b(color|blendColor|width|height|translation|size|itemSize|itemSpacing|rowHeights|rowItemSize|rowItemSpacing|rowSpacings|focusXOffset|numRows|numColumns|font|opacity|lineSpacing|scale|maxWidth|maxLines)\s*=\s*"[^"]*\d[^"]*"/;
const problems = [];
(function walk(dir) {
  for (const name of readdirSync(dir)) {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) { walk(path); continue; }
    const lines = readFileSync(path, 'utf8').split('\n');
    lines.forEach((line, index) => {
      const where = `${relative(app, path)}:${index + 1}`;
      if (name.endsWith('.xml')) {
        if (/<field\b/.test(line) || /<\?xml/.test(line)) return;
        if (layoutAttributes.test(line) || /0x[0-9a-fA-F]{6,8}|#[0-9a-fA-F]{6}\b/.test(line)) problems.push(`${where}: a literal in component XML: ${line.trim()}`);
        return;
      }
      if (!name.endsWith('.bs')) return;
      const code = line.replace(/'.*$/, '').replace(/"(?:[^"]|"")*"/g, m => (/^"(0x[0-9a-fA-F]{6,8}|#[0-9a-fA-F]{6,8})"$/.test(m) ? 'COLOUR' : '""'));
      if (code.includes('COLOUR') || /&h[0-9a-fA-F]+/.test(code)) problems.push(`${where}: a colour literal: ${line.trim()}`);
      for (const m of code.matchAll(/(?<![A-Za-z_.\d])(\d+(?:\.\d+)?)(?![\w.])/g)) if (!allowed.has(m[1])) problems.push(`${where}: the number ${m[1]} (read it from Theme): ${line.trim()}`);
    });
  }
})(join(app, 'components'));
if (problems.length) {
  console.error(problems.join('\n'));
  console.error(`lint-literals: ${problems.length} literal(s) in components/`);
  process.exit(1);
}
console.log('lint-literals: components/ is literal-free');

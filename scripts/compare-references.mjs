import {existsSync, mkdirSync} from 'node:fs';
import {join, resolve} from 'node:path';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

const root = resolve(fileURLToPath(new URL('..', import.meta.url)));
const screenshots = resolve(root, '../artifacts/screenshots');
const output = join(root, 'artifacts/comparisons');
mkdirSync(output, {recursive: true});

const comparisons = [
  ['home-default', 'home-default.png', 'portico-four-tv-home-shell-pass4.png'],
  ['home-rail-expanded', 'home-rail-expanded.png', 'portico-four-tv-rail-expanded-transform.png'],
  ['home-rookie-focused', 'home-rookie-focused.png', 'portico-four-tv-home-rookie-focus.png'],
  ['detail-rookie', 'detail-rookie.png', 'portico-four-tv-detail-no-utilities.png'],
  ['library-grid', 'library-grid.png', 'portico-four-tv-library-pass2.png'],
  ['player-playing', 'player-playing.png', 'portico-four-tv-player-full-bleed-pass2.png']
];

function run(argumentsList) {
  const result = spawnSync('magick', argumentsList, {encoding: 'utf8'});
  if (result.status !== 0) throw new Error(`ImageMagick failed: ${result.stderr}`);
}

for (const [name, goldenName, referenceName] of comparisons) {
  const golden = join(root, 'artifacts/golden', goldenName);
  const reference = join(screenshots, referenceName);
  if (!existsSync(golden)) throw new Error(`Missing golden: ${golden}`);
  if (!existsSync(reference)) throw new Error(`Missing reference: ${reference}`);
  run([reference, '-resize', '960x540!', golden, '-resize', '960x540!', '+append', join(output, `${name}-side-by-side.png`)]);
  run([reference, golden, '-compose', 'difference', '-composite', join(output, `${name}-difference.png`)]);
  console.log(`Compared ${name} (tvOS reference left, deterministic Roku contract right).`);
}

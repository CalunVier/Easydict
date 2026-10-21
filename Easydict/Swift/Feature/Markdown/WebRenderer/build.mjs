import { build } from 'esbuild';
import { cp, mkdir, readFile, readdir, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

// Checked-in output lets Xcode build offline without Node or npm.
const here = path.dirname(fileURLToPath(import.meta.url));
const output = path.resolve(here, '../MarkdownResources');
await mkdir(output, { recursive: true });
await build({ entryPoints: [path.join(here, 'renderer.js')], bundle: true,
    outfile: path.join(output, 'renderer.js'), minify: true, target: 'safari16', legalComments: 'eof' });
for (const name of ['index.html', 'renderer.css']) await cp(path.join(here, name), path.join(output, name));
const katex = path.join(here, 'node_modules/katex');
await cp(path.join(katex, 'dist/katex.min.css'), path.join(output, 'katex.min.css'));
await cp(path.join(katex, 'dist/fonts'), path.join(output, 'fonts'), { recursive: true });
const licenses = [];
const lock = JSON.parse(await readFile(path.join(here, 'package-lock.json'), 'utf8'));
for (const [location, info] of Object.entries(lock.packages)) {
    if (!location || info.dev || info.optional) continue;
    const directory = path.join(here, location);
    const files = await readdir(directory);
    const license = files.find(name => /^licen[cs]e(?:[.\-]|$)/i.test(name));
    if (!license) throw new Error(`Missing license: ${location}`);
    licenses.push(`\n--- ${location.replace('node_modules/', '')} ${info.version} ---\n` +
        await readFile(path.join(directory, license), 'utf8'));
}
await writeFile(path.join(output, 'LICENSES.txt'), licenses.join('\n'));
const manifest = {};
async function digest(directory, prefix = '') {
    for (const entry of (await readdir(directory, { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name, 'en'))) {
        const relative = prefix + entry.name;
        if (entry.isDirectory()) await digest(path.join(directory, entry.name), relative + '/');
        else if (relative !== 'SHA256.json') manifest[relative] = createHash('sha256').update(await readFile(path.join(directory, entry.name))).digest('hex');
    }
}
await digest(output);
await writeFile(path.join(output, 'SHA256.json'), JSON.stringify(manifest, null, 2) + '\n');

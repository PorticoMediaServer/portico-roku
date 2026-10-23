// Normal MAIN-only source intake for the Roku §33 port; no caller palette or fixture synthesis.
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync,renameSync} from 'node:fs';
import {dirname,join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
const app=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const root=process.env.PORTICO_SERVER_ROOT;
if(!root)throw new Error('Set PORTICO_SERVER_ROOT to the checked Server Git repository');
const pin=JSON.parse(readFileSync(join(app,'scripts/channel-tint-source-pins.json'),'utf8'));
execFileSync('git',['merge-base','--is-ancestor',pin.commit,'origin/main'],{cwd:root});
const sources={};
for(const [path,expected] of Object.entries(pin.files)){
 const bytes=execFileSync('git',['show',pin.commit+':'+path],{cwd:root});
 if(createHash('sha256').update(bytes).digest('hex')!==expected)throw new Error('Canonical input changed: '+path);
 sources[path]=bytes;
}
const body=sources['packages/client-core/src/presentation/kit-model/channels.ts'].toString('utf8');
const palette=/const channelTints = (\[[^\n]+\]) as const;/.exec(body)?.[1];
if(!palette||!body.includes('hash * 31 + seed.charCodeAt(index)')||!body.includes('Math.abs(hash) % channelTints.length'))throw new Error('Review the native port against the new canonical algorithm');
const colors=JSON.parse(palette.replaceAll("'",'"'));
if(colors.length!==8||new Set(colors).size!==8||colors.some(c=>!/^#[0-9a-f]{6}$/.test(c)))throw new Error('Unexpected canonical palette');
const emit=(path,bytes)=>{
 const target=join(app,path);
 if(process.argv.includes('--check')){if(!readFileSync(target).equals(Buffer.from(bytes)))throw new Error('Regenerate '+path);}
 else{writeFileSync(target+'.tmp',bytes);renameSync(target+'.tmp',target);}
};
emit('source/core/ChannelTintPalette.bs',`' Exact MAIN ${pin.commit} channelTint palette, in canonical order.\nfunction ChannelTintPalette() as object\n    return ${JSON.stringify(colors)}\nend function\n`);
emit('test/fixtures/channel-tint-vectors.json',sources['packages/client-core/test/fixtures/channel-tint-vectors.json']);
console.log('Channel tint: exact MAIN palette and independent shared vectors');

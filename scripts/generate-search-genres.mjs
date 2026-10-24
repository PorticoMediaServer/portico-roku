// Narrow exact MAIN contract intake; other route/catalogue/source pins are unchanged.
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {readFileSync,writeFileSync,renameSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
import {dirname,join,resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
const app=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const root=process.env.PORTICO_SERVER_ROOT, internal=process.env.PORTICO_INTERNAL_ROOT;
if(!root||!internal)throw new Error('Set checked Server and immutable design repository paths');
const pin=JSON.parse(readFileSync(join(app,'scripts/search-genres-source-pins.json'),'utf8'));
execFileSync('git',['merge-base','--is-ancestor',pin.commit,'origin/main'],{cwd:root});
const source={};
for(const [path,hash] of Object.entries(pin.files)){
 const bytes=execFileSync('git',['show',pin.commit+':'+path],{cwd:root,maxBuffer:16*1024*1024});
 if(createHash('sha256').update(bytes).digest('hex')!==hash)throw new Error('Changed canonical input: '+path);
 source[path]=bytes.toString('utf8');
}
const {schemas}=await import('data:text/javascript;base64,'+Buffer.from(stripTypeScriptTypes(source['packages/contracts/src/schemas.ts'])).toString('base64'));
const page=schemas.GetSearchGenresResponse,genre=page?.properties?.genres?.items;
const route=/"get_search_genres": "([^"]+)"/.exec(source['packages/contracts/src/routes.ts'])?.[1];
const core=source['packages/client-core/src/search-genres.ts'];
if(!route||page.required.join(',')!=='revision,genres'||genre.required.join(',')!=='value,label,count,covers'||genre.properties.covers.maxItems!==2)throw new Error('Review genre DTO port');
for(const fragment of ['input.genres.length > 50',"text(raw.revision, 1024)","text(raw.nextCursor, 4096)","text(genre.value, 1024)","text(value.path, 2048)","role === 'backdrop' ? '1920' : '400'"]){if(!core.includes(fragment))throw new Error('Review canonical genre validator: '+fragment);}
const design='69f2d45a972ff9ec1bd8743c760183026c92d555';
const states=execFileSync('git',['show',design+':design/ui-v1/states.html'],{cwd:internal}).toString();
const start=states.indexOf('id="f18"'),end=states.indexOf('<!--',start);
if(start<0||end<start)throw new Error('Missing TV empty-search frame');
const prefix=(states.slice(start,end).match(/<button class="gtl\b/g)??[]).length;
if(prefix!==4)throw new Error('Review drawn TV prefix');
const values={path:route,maximumPage:50,maximumCovers:genre.properties.covers.maxItems,minimumCount:genre.properties.count.minimum,maximumCount:genre.properties.count.maximum,artKinds:genre.properties.backdrop.properties.kind.enum,tvPrefix:prefix};
const text=`' Exact Server MAIN ${pin.commit}; drawn prefix states.html#f18 at ${design}.\nnamespace SearchGenreContract\n${Object.entries(values).map(([k,v])=>'    const '+k+' = '+(k==='maximumCount'?String(v)+'#':JSON.stringify(v))).join('\n')}\nend namespace\n`;
const target=join(app,'source/core/SearchGenreContract.bs');
if(process.argv.includes('--check')){if(readFileSync(target,'utf8')!==text)throw new Error('Regenerate genre contract');}
else{writeFileSync(target+'.tmp',text);renameSync(target+'.tmp',target);}
console.log('Search genre MAIN contract: mounted read, strict art slots, TV prefix4; other pins preserved');

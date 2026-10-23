// Exact immutable identity frames3/4, including their drawn symbol geometry.
import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync,renameSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {resolve,dirname,join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {Resvg} from '@resvg/resvg-js';
import {deflateSync,crc32} from 'node:zlib';
const app=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const assets=JSON.parse(readFileSync(join(app,'scripts/auth-assets-source-pins.json')));
const load=(root,commit,path,hash)=>{const bytes=execFileSync('git',['show',commit+':'+path],{cwd:root});if(createHash('sha256').update(bytes).digest('hex')!==hash)throw new Error('Source mismatch '+path);return bytes.toString();};
const internal=assets.inputs.find(x=>x.root==='internal'),path='design/ui-v1/server-identity.html';
const html=load(process.env.PORTICO_INTERNAL_ROOT,internal.commit,path,internal.files[path]);
const rule=selector=>[...html.matchAll(new RegExp(selector.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')+' \\{([^}]+)\\}','g'))].map(x=>x[1]).join(';');
const px=(css,key)=>{const v=[...css.matchAll(new RegExp('(?:^|;)\\s*'+key+':\\s*(-?[.\\d]+)px','g'))].at(-1)?.[1];if(v===undefined)throw new Error('Missing '+key);return Number(v);};
const frame=/data-f="3"[\s\S]*?<\/div><\/div>/.exec(html)?.[0];if(!frame)throw new Error('Missing frame3');
const width=Number(/class="tst" style="width:(\d+)px"/.exec(frame)?.[1]);if(!width)throw new Error('Missing state width');
const emit=(name,bytes)=>{const p=join(app,name),b=Buffer.from(bytes);if(process.argv.includes('--check')){if(!readFileSync(p).equals(b))throw new Error('Regenerate '+name);}else{writeFileSync(p+'.tmp',b);renameSync(p+'.tmp',p);}};
const m={width,left:px(rule('.screen.tv'),'--gutter'),circle:px(rule('.tst .st-ic'),'width'),circleGap:px(rule('.tst .st-ic'),'margin-bottom'),iconSize:Number(/class="st-ic err"><svg width="(\d+)"/.exec(frame)[1]),titleSize:px(rule('.tst h1'),'font-size'),titleGap:24,titleTracking:-.045,bodyWidth:px(rule('.tst .body'),'max-width'),bodySize:px(rule('.tst .body'),'font-size'),bodyLineHeight:1.45,bodyGap:40,actionGap:px(rule('.tst .actions'),'gap'),dialogWidth:px(rule('.tdlg'),'width'),dialogRadius:px(rule('.tdlg'),'border-radius'),dialogTop:56,dialogSide:60,dialogBottom:52,dialogTitle:px(rule('.tdlg h2'),'font-size'),dialogTracking:-.035,dialogTitleGap:16,dialogBodyGap:34,dialogActionGap:px(rule('.tdlg .actions'),'gap'),scrim:'0x03080CA8',circleAlpha:.1,circleBorderAlpha:.12,dialogBorder:1.5,dialogBorderAlpha:.12,railWidth:px(rule('.rail'),'width'),railLeft:72,railTop:58,railBottom:56,brandInset:16,brandWidth:28,brandHeight:40,brandGap:64,railItem:64,railIcon:30,railIconInset:17,railBarWidth:4,railBarHeight:28,railBarOffset:16,railBarTop:18,buttonIcon:28};
// Verify the shorthands/ratios rather than silently accepting a changed design declaration.
for(const [s,fragment]of [['.tst h1','margin: 0 0 24px'],['.tst h1','letter-spacing: -.045em'],['.tst .body','line-height: 1.45'],['.tst .body','margin: 0 0 40px'],['.tdlg','padding: 56px 60px 52px'],['.tdlg h2','letter-spacing: -.035em'],['.tdlg h2','margin: 0 0 16px'],['.tdlg p','margin: 0 0 34px'],['.scrim-t','rgba(3,8,12,.66)'],['.rail','padding: 58px 0 56px 72px'],['.rail .brand','margin: 0 0 64px 16px']])if(!rule(s).includes(fragment))throw new Error('Re-read '+s+' '+fragment);
const font=readFileSync(join(app,'fonts/manrope-800.ttf'));const tables={};for(let i=0;i<font.readUInt16BE(4);i++){const at=12+i*16;tables[font.toString('ascii',at,at+4)]=font.readUInt32BE(at+8);}const units=font.readUInt16BE(tables.head+18);m.titleOffsetRatio=-((font.readInt16BE(tables.hhea+4)-font.readInt16BE(tables.hhea+6)+font.readInt16BE(tables.hhea+8))/units-1)/2;
m.bodyLineSpacing=m.bodySize*m.bodyLineHeight-m.bodySize*(1-m.titleOffsetRatio*2);m.bodyLeading=m.bodyLineSpacing/2;
const shadow=/0 (\d+)px (\d+)px (-?\d+)px #000/.exec(rule('.tdlg'));if(!shadow)throw new Error('Missing dialog shadow');m.shadowOffset=Number(shadow[1]);m.shadowBlur=Number(shadow[2]);m.shadowSpread=Number(shadow[3]);m.shadowMargin=m.shadowBlur*2;m.shadowMaxLines=12;
const iconSpecs=[['shieldx',m.iconSize,'shieldx'],['retry',m.buttonIcon,'retry'],['home',m.railIcon,'identityHome'],['settings',m.railIcon,'identitySettings'],['server',m.buttonIcon,'identityServer'],['question',m.iconSize,'identityQuestion']];
const iconPaths=Object.fromEntries(iconSpecs.map(([name,size,id])=>[id,`pkg:/images/icons/identity-${name}-${size}.png`]));
emit('source/ui/IdentityFrameMetrics.bs',`' Generated from ${internal.commit}:${path}, frames3/4.\nnamespace IdentityFrameMetrics\n${Object.entries(m).map(([k,v])=>'    const '+k+' = '+JSON.stringify(v)).join('\n')}\nend namespace\n\nfunction IdentityFrameIconPaths() as object\n    return ${JSON.stringify(iconPaths)}\nend function\n`);
for(const[name,size]of iconSpecs){
 // Use the frame's symbols: the shared kit has different server/settings/retry paths.
 const body=new RegExp('<symbol id="i-'+name+'"[^>]*>([\\s\\S]*?)</symbol>').exec(html)?.[1];
 if(!body)throw new Error('Missing canonical '+name);
 const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 24 24">${body.replaceAll('currentColor','#fff')}</svg>`;
 emit(`images/icons/identity-${name}-${size}.png`,new Resvg(svg).render().asPng());
}
console.log('identity metrics/icons verified: immutable69 frames, six exact drawn symbols');
// A bounded check for icon-only changes; the default still verifies every generated asset.
if(process.argv.includes('--icons-only'))process.exit(0);
const rail=`<svg xmlns="http://www.w3.org/2000/svg" width="${m.railWidth}" height="1080"><defs><linearGradient id="r"><stop stop-color="#071018" stop-opacity=".78"/><stop offset="45%" stop-color="#071018" stop-opacity=".42"/><stop offset="100%" stop-color="#071018" stop-opacity="0"/></linearGradient></defs><rect width="100%" height="100%" fill="url(#r)"/></svg>`;
if(!rule('.rail').includes('rgba(7,16,24,.78) 0, rgba(7,16,24,.42) 45%, rgba(7,16,24,0) 100%'))throw new Error('Re-read rail gradient');
emit('images/gradients/identity-rail.png',new Resvg(rail).render().asPng());
console.log('identity rail/shadows: immutable69 frames3/4');

for(let lines=1;lines<=m.shadowMaxLines;lines++){
 const height=m.dialogTop+lines*m.dialogTitle*(1-m.titleOffsetRatio*2)+m.dialogTitleGap+2*m.bodySize*m.bodyLineHeight+m.dialogBodyGap+72+m.dialogBottom;
 const margin=m.shadowMargin,spread=m.shadowSpread;
 const svg=`<svg xmlns="http://www.w3.org/2000/svg" width="${m.dialogWidth+margin*2}" height="${Math.ceil(height+margin*2)}"><defs><filter id="blur" x="-100%" y="-300%" width="300%" height="700%"><feGaussianBlur stdDeviation="${m.shadowBlur/2}"/></filter></defs><rect x="${margin-spread}" y="${margin+m.shadowOffset-spread}" width="${m.dialogWidth+spread*2}" height="${height+spread*2}" rx="${Math.max(0,m.dialogRadius+spread)}" fill="#000" filter="url(#blur)"/></svg>`;
 emit(`images/shapes/identity-dialog-shadow-${lines}.png`,blackAlphaPng(new Resvg(svg).render()));
}
const radius=m.dialogRadius,side=radius*2+2,stroke=m.dialogBorder;
const border=`<svg xmlns="http://www.w3.org/2000/svg" width="${side+2}" height="${side+2}"><rect x="${1+stroke/2}" y="${1+stroke/2}" width="${side-stroke}" height="${side-stroke}" rx="${radius-stroke/2}" fill="none" stroke="white" stroke-width="${stroke}"/><rect x="${1+side/2}" y="0" width="1" height="1" fill="black"/><rect x="0" y="${1+side/2}" width="1" height="1" fill="black"/></svg>`;
emit('images/shapes/identity-dialog-border.9.png',new Resvg(border).render().asPng());

// The shadow has one colour and 256 alpha values. Indexed PNG preserves every rendered
// pixel while keeping all bounded heading heights inside Roku's package budget.
function blackAlphaPng(image){
 const {width,height,pixels}=image,raw=Buffer.alloc((width+1)*height);
 for(let y=0;y<height;y++)for(let x=0;x<width;x++){const i=(y*width+x)*4;if(pixels[i]||pixels[i+1]||pixels[i+2])throw new Error('Shadow is not black');raw[y*(width+1)+1+x]=pixels[i+3];}
 const chunk=(name,body)=>{const type=Buffer.from(name),size=Buffer.alloc(4),crc=Buffer.alloc(4);size.writeUInt32BE(body.length);crc.writeUInt32BE(crc32(Buffer.concat([type,body])));return Buffer.concat([size,type,body,crc]);};
 const header=Buffer.alloc(13);header.writeUInt32BE(width);header.writeUInt32BE(height,4);header[8]=8;header[9]=3;
 return Buffer.concat([Buffer.from('89504e470d0a1a0a','hex'),chunk('IHDR',header),chunk('PLTE',Buffer.alloc(256*3)),chunk('tRNS',Buffer.from(Array.from({length:256},(_,i)=>i))),chunk('IDAT',deflateSync(raw,{level:9})),chunk('IEND',Buffer.alloc(0))]);
}

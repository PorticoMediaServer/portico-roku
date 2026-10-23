// VPS Chrome view of the compiled Roku component, never a physical/SG Task acceptance test.
import {createServer} from 'node:http';
import {readFileSync,writeFileSync,mkdirSync,existsSync} from 'node:fs';
import {resolve,join,dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';
import {chromium} from 'playwright-core';

const app=resolve(dirname(fileURLToPath(import.meta.url)),'..');
const build=process.env.PORTICO_BUILD_DIR;
const output=process.env.PORTICO_RUNNER_OUTPUT;
if(!build||!output)throw new Error('Set owned PORTICO_BUILD_DIR and PORTICO_RUNNER_OUTPUT');
mkdirSync(output,{recursive:true});
const fixture=join(build,'visual-identity.zip');
const fixtureLog=execFileSync('python3',[join(app,'scripts/visual-identity-fixture.py'),join(build,'portico-roku.zip'),fixture],{encoding:'utf8'});
const files=new Map([
 ['/brs.api.js',[join(app,'node_modules/brs-engine/lib/brs.api.js'),'text/javascript']],
 ['/brs.worker.js',[join(app,'node_modules/brs-engine/lib/brs.worker.js'),'text/javascript']],
 ['/brs-sg.js',[join(app,'node_modules/brs-scenegraph/lib/brs-sg.js'),'text/javascript']],
 ['/common.zip',[join(app,'node_modules/brs-scenegraph/assets/common.zip'),'application/zip']],
 ['/visual-identity.zip',[fixture,'application/zip']]
]);
const html=`<!doctype html><meta charset="utf-8"><title>Roku identity component comparison</title>
<style>html,body{margin:0;background:#000;width:1920px;height:1080px;overflow:hidden}#display,#player{position:absolute;inset:0;width:1920px;height:1080px}#player{z-index:-1}</style>
<canvas id="display" width="1920" height="1080"></canvas><video id="player"></video><script src="/brs.api.js"></script><script>
window.engineEvents=[];
brs.subscribe('visual-identity',(event,data)=>engineEvents.push({event,data}));
(async()=>{
 const assets=await(await fetch('/common.zip')).arrayBuffer();
 await brs.initialize({displayMode:'1080p',locale:'en_US',maxFps:30,assets,registry:new Map(),extensions:new Map([[brs.SupportedExtension.SceneGraph,location.origin+'/brs-sg.js']])},{debugToConsole:true});
 const payload=await(await fetch('/visual-identity.zip')).arrayBuffer();
 brs.execute('visual-identity.zip',payload,{clearDisplayOnExit:false});
})().catch(error=>engineEvents.push({setupError:String(error)}));
</script>`;
const server=createServer((req,res)=>{
 res.setHeader('Cross-Origin-Opener-Policy','same-origin');
 res.setHeader('Cross-Origin-Embedder-Policy','require-corp');
 res.setHeader('Cache-Control','no-store');
 const path=new URL(req.url,'http://127.0.0.1').pathname;
 if(path==='/'){res.setHeader('Content-Type','text/html');res.end(html);return;}
 const file=files.get(path);
 if(!file){diagnostics.push('HTTP404 '+req.url);res.writeHead(404);res.end();return;}
 res.setHeader('Content-Type',file[1]);res.end(readFileSync(file[0]));
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
let browser,page,failure;
const diagnostics=[];
try{
 browser=await chromium.launch({executablePath:process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH,headless:true,args:['--disable-dev-shm-usage']});
 const context=await browser.newContext({viewport:{width:1920,height:1080},deviceScaleFactor:1,locale:'en-US',colorScheme:'dark'});
 page=await context.newPage();
 page.on('pageerror',error=>diagnostics.push(String(error)));
 page.on('console',message=>{if(message.type()==='error'||message.type()==='warning')diagnostics.push('console '+message.type()+': '+message.text());});
 page.on('requestfailed',request=>diagnostics.push('requestfailed '+request.url()+': '+request.failure()?.errorText));
 await page.goto('http://127.0.0.1:'+server.address().port);
 diagnostics.push(JSON.stringify(await page.evaluate(()=>({crossOriginIsolated,SharedArrayBuffer:typeof SharedArrayBuffer,OffscreenCanvas:typeof OffscreenCanvas}))));
 await page.waitForFunction(()=>window.engineEvents.some(e=>String(e.data?.content).includes('VISUAL_IDENTITY_READY')),{},{timeout:60000});
 // Read actual rendered pixels; this never paints or compensates the simulator's output.
 await page.waitForFunction(()=>{
  const c=document.querySelector('#display'),ctx=c.getContext('2d');
  if(!ctx)return false;
  const p=ctx.getImageData(200,420,920,145).data;let bright=0;
  for(let i=0;i<p.length;i+=4)if(p[i]>180&&p[i+1]>180&&p[i+2]>180)bright++;
  return bright>4000;
 },{},{timeout:60000});
 await page.screenshot({path:join(output,'identity-3.jpg'),type:'jpeg',quality:96});
 for(const key of ['ArrowRight','ArrowRight','Enter']){
  await page.keyboard.press(key);
  // Allow the worker's real remote-control queue and focus animation to complete a frame.
  await page.waitForTimeout(180);
 }
 await page.waitForFunction(()=>{
  const p=document.querySelector('#display').getContext('2d').getImageData(480,400,1,1).data;
  return p[1]>25&&p[2]>30;
 },{},{timeout:15000});
 await page.screenshot({path:join(output,'identity-4.jpg'),type:'jpeg',quality:96});
 await page.keyboard.press('Escape');
 await page.waitForFunction(()=>document.querySelector('#display').getContext('2d').getImageData(480,400,1,1).data[1]<25,{},{timeout:15000});
 await page.screenshot({path:join(output,'identity-return.jpg'),type:'jpeg',quality:96});
 const events=await page.evaluate(()=>window.engineEvents);
 for(const e of events)if(e.event==='debug'||e.setupError)diagnostics.push(JSON.stringify(e));
 console.log(fixtureLog+'Captured identity3/4/Back at1920x1080 in VPS Chromium; COMPONENT-ONLY, comparison still required.');
 await context.close();
}catch(error){
 failure=error;
 diagnostics.push(String(error.stack??error));
 if(page&&!page.isClosed()){
  for(const name of ['identity-3.jpg','identity-4.jpg','identity-return.jpg']){
   if(!existsSync(join(output,name)))await page.screenshot({path:join(output,name),type:'jpeg',quality:96}).catch(()=>{});
  }
  diagnostics.push(JSON.stringify(await page.evaluate(()=>window.engineEvents.filter(e=>e.event!=='icon')).catch(()=>[])));
 }
 throw error;
}finally{
 writeFileSync(join(output,'identity-capture.log'),fixtureLog+'Status: '+(failure?'ERROR; captured diagnostics only':'CAPTURED; visual comparison still required')+'\nChrome '+(browser?.version()??'not launched')+'; viewport1920x1080; deviceScaleFactor1\nRequested remote sequence: Right, Right, Enter, Back; component-only synthetic state.\nNo full host, native Task, HTTP/TLS, physical Group.scale or hardware acceptance.\n'+diagnostics.join('\n')+'\n');
 if(browser)await browser.close();
 await new Promise(resolve=>server.close(resolve));
}

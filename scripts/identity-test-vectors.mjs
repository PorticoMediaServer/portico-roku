// Independent Node crypto vectors. Expectations below are authored from the checked wire
// contract, never obtained by calling the Roku or canonical parser under test.
import {createHash,createPrivateKey,createPublicKey,sign,verify} from 'node:crypto';
import {readFileSync,writeFileSync,renameSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
const key=createPrivateKey({key:Buffer.from('302e020100300506032b657004220420'+'01'.repeat(32),'hex'),format:'der',type:'pkcs8'});
const pub=createPublicKey(key),raw=pub.export({format:'der',type:'spki'}).subarray(-32);
const digests=new Map(),verdicts=[];
const digest=(algorithm,input)=>{const value=createHash(algorithm).update(input).digest();digests.set(algorithm+input.toString('hex'),{algorithm,input:input.toString('hex'),digest:value.toString('hex')});return value;};
const pin={serverId:'srv_'+digest('sha256',Buffer.concat([Buffer.from('portico.server.identity.v1\0'),raw])).toString('base64url'),publicKey:raw.toString('base64url'),fingerprint:digest('sha256',raw).toString('base64url')};
const origin='http://192.168.1.20:32500',nonce=Buffer.alloc(32,7).toString('base64url'),now=Date.parse('2026-10-23T12:00:10Z')/1000;
const leaf=Buffer.alloc(32,8).toString('base64url');
const base={kind:'portico.route-proof',version:'2',baseUrl:origin,nonce,...pin,issuedAt:'2026-10-23T12:00:00Z',expiresAt:'2026-10-23T12:00:30Z',tlsCertificateFingerprints:[leaf]};
const cases=[];
function vector(name,change,ok,code,tamper=false){
 const body={...base};change(body);let payload=Buffer.from(JSON.stringify(body)),signature=sign(null,payload,key);
 if(tamper){body.nonce='tampered';payload=Buffer.from(JSON.stringify(body));}
 const d=digest('sha512',Buffer.concat([signature.subarray(0,32),raw,payload]));
 verdicts.push({publicKey:raw.toString('hex'),signature:signature.toString('hex'),digest:d.toString('hex'),valid:verify(null,payload,pub,signature)});
 cases.push({name,answer:{payload:payload.toString('base64url'),signature:signature.toString('base64url')},origin,nonce:tamper?'tampered':nonce,pin,now,ok,...(code?{code}:{})});
}
vector('signed v2 bounded leaf declarations',()=>{},true);
vector('v2 without leaf declarations is valid under public CA/home HTTP',b=>delete b.tlsCertificateFingerprints,true);
vector('v1 remains strictly field bound',b=>{b.version='1';delete b.tlsCertificateFingerprints;},true);
vector('v1 cannot smuggle leaf declarations',b=>b.version='1',false,'invalid_identity');
vector('empty list',b=>b.tlsCertificateFingerprints=[],false,'invalid_identity');
vector('duplicate list',b=>b.tlsCertificateFingerprints=[leaf,leaf],false,'invalid_identity');
vector('more than eight declarations',b=>b.tlsCertificateFingerprints=Array.from({length:9},(_,i)=>Buffer.alloc(32,i).toString('base64url')),false,'invalid_identity');
vector('noncanonical fingerprint',b=>b.tlsCertificateFingerprints=['bad'],false,'invalid_identity');
vector('unknown field',b=>b.approval=true,false,'invalid_identity');
vector('unknown version',b=>b.version='3',false,'identity_mismatch');
vector('wrong origin',b=>b.baseUrl='https://other.example',false,'identity_mismatch');
vector('wrong nonce',b=>b.nonce='other',false,'identity_mismatch');
vector('tampered signature',()=>{},false,'identity_mismatch',true);
vector('strict UTC date remains mandatory',b=>b.expiresAt='2026-02-30T12:00:30Z',false,'route_stale');
vector('expired evidence',b=>{b.issuedAt='2026-10-23T11:59:00Z';b.expiresAt='2026-10-23T11:59:30Z';},false,'route_stale');
// The preserved historical clock cases predate signature-before-clock ordering. Their
// signatures are valid, but the old fixture never recorded those digest/verdict operations.
// Supply only independent crypto facts; do not rewrite that golden or its expectations.
const legacy=JSON.parse(readFileSync(new URL('../test/fixtures/golden/route-identity.json',import.meta.url),'utf8'));
for(const item of legacy.proofs.filter(item=>item.code==='route_stale')){
 const payload=Buffer.from(item.answer.payload,'base64url'),signature=Buffer.from(item.answer.signature,'base64url'),document=JSON.parse(payload),publicKey=Buffer.from(document.publicKey,'base64url');
 const key=createPublicKey({key:Buffer.concat([Buffer.from('302a300506032b6570032100','hex'),publicKey]),format:'der',type:'spki'});
 const d=digest('sha512',Buffer.concat([signature.subarray(0,32),publicKey,payload]));
 if(!verify(null,payload,key,signature))throw new Error('Preserved clock proof has invalid signature: '+item.name);
 verdicts.push({publicKey:publicKey.toString('hex'),signature:signature.toString('hex'),digest:d.toString('hex'),valid:true});
}
const path=fileURLToPath(new URL('../test/fixtures/identity-main38.json',import.meta.url)),temp=path+'.tmp';
writeFileSync(temp,JSON.stringify({provenance:'Independent Node Ed25519/SHA vectors; manually authored expectations',pin,origin,nonce,now,digests:[...digests.values()],verdicts,cases},null,2)+'\n');renameSync(temp,path);

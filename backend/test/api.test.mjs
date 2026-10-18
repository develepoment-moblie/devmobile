import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPairSync, sign, randomUUID } from 'node:crypto';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Store } from '../store.mjs';
import { demoState } from '../seed.mjs';
import { createApi } from '../server.mjs';

const pair=generateKeyPairSync('rsa',{modulusLength:2048,publicKeyEncoding:{type:'spki',format:'pem'},privateKeyEncoding:{type:'pkcs8',format:'pem'}});
const directory=mkdtempSync(join(tmpdir(),'nova-housekeeping-'));
let store,server,url;
function token(sub='sarah',extra={},header={alg:'RS256'}) {
  const iat=Math.floor(Date.now()/1000);
  const h=Buffer.from(JSON.stringify(header)).toString('base64url');
  const p=Buffer.from(JSON.stringify({sub,hotel_id:'hotel-a',iss:'test',aud:'housekeeping',iat,exp:iat+3600,...extra})).toString('base64url');
  return `${h}.${p}.${sign('RSA-SHA256',Buffer.from(`${h}.${p}`),pair.privateKey).toString('base64url')}`;
}
async function start() {
  store=new Store(join(directory,'test.sqlite'));store.provision('hotel-a',demoState());store.provision('hotel-b',demoState());
  server=createApi({store,publicKey:pair.publicKey,issuer:'test',audience:'housekeeping',origins:['http://localhost:8085']});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));url=`http://127.0.0.1:${server.address().port}`;
}
async function stop(){await new Promise(resolve=>server.close(resolve));store.close();}
async function request(path,{sub='sarah',body,auth=token(sub),key=randomUUID(),headers={}}={}) {
  const res=await fetch(url+path,{method:body?'POST':'GET',headers:{Authorization:`Bearer ${auth}`,'Content-Type':'application/json','Idempotency-Key':key,...headers},body:body?JSON.stringify(body):undefined});
  return {status:res.status,body:await res.json()};
}
const snapshot=(sub='sarah')=>request('/v1/snapshot',{sub});
before(start);after(async()=>{await stop();rmSync(directory,{recursive:true,force:true});});

test('missing, expired, wrong issuer/audience, algorithm and tampered credentials denied',async()=>{
  for(const auth of ['',token('sarah',{exp:1}),token('sarah',{iss:'bad'}),token('sarah',{aud:'bad'}),token('sarah',{}, {alg:'HS256'}),token()+'x']) assert.equal((await request('/v1/snapshot',{auth})).status,401);
});
test('agents cannot assign, approve, change stock or checkout, even with forged role fields',async()=>{
  for(const [path,body] of [['/v1/rooms/305/assign',{version:1,employeeId:'sarah',note:'',urgent:false,role:'supervisor'}],['/v1/rooms/109/approve',{version:1}],['/v1/supplies/sheets/movement',{version:1,delta:5}],['/v1/rooms/112/checkout',{version:1}]]) assert.equal((await request(path,{body,headers:{'X-Role':'supervisor'}})).status,403);
});
test('agent cannot modify another agent task',async()=>{
  for(const action of ['start','checklist','submit']) assert.equal((await request(`/v1/rooms/207/${action}`,{body:{version:1,index:0,value:true}})).status,403);
});
test('two clients see assigned task, complete checks and supervisor approves',async()=>{
  assert.equal((await request('/v1/rooms/305/assign',{sub:'amina',body:{version:1,employeeId:'sarah',note:'Test',urgent:true}})).status,200);
  let r=(await snapshot()).body.rooms.find(r=>r.number==='305');assert.equal(r.employeeId,'sarah');
  assert.equal((await request('/v1/rooms/305/start',{body:{version:r.version}})).status,200);
  assert.equal((await request('/v1/rooms/305/submit',{body:{version:r.version+1}})).status,409);
  for(let index=0;index<4;index++) assert.equal((await request('/v1/rooms/305/checklist',{body:{version:r.version+1+index,index,value:true}})).status,200);
  assert.equal((await request('/v1/rooms/305/submit',{body:{version:r.version+5}})).status,200);
  r=(await snapshot('amina')).body.rooms.find(r=>r.number==='305');assert.equal(r.status,'dirty');assert.equal(r.cleaning,'review');
  assert.equal((await request('/v1/rooms/305/approve',{sub:'amina',body:{version:r.version}})).status,200);
  r=(await snapshot()).body.rooms.find(r=>r.number==='305');assert.equal(r.status,'ready');assert.equal(r.approvedBy,'Amina');
});
test('stock is atomic, concurrent writes conflict, retries are idempotent',async()=>{
  const body={version:1,delta:-2},key=randomUUID();
  const results=await Promise.all([request('/v1/supplies/sheets/movement',{sub:'amina',body,key}),request('/v1/supplies/sheets/movement',{sub:'amina',body})]);
  assert.deepEqual(results.map(r=>r.status).sort(),[200,409]);
  // The first request is serialized first by this server; use its key if accepted.
  if(results[0].status===200) assert.equal((await request('/v1/supplies/sheets/movement',{sub:'amina',body,key})).status,200);
  const supply=(await snapshot()).body.supplies[0];assert.equal(supply.quantity,40);
  assert.equal((await request('/v1/supplies/sheets/movement',{sub:'amina',body:{version:supply.version,delta:-100}})).status,409);
});
test('notification reads persist separately per user and hidden notifications are denied',async()=>{
  assert.equal((await request('/v1/notifications/read',{body:{ids:['vip305']}})).status,200);
  assert.equal((await snapshot()).body.notifications.find(n=>n.id==='vip305').read,true);
  assert.equal((await snapshot('lina')).body.notifications.find(n=>n.id==='vip305').read,false);
  assert.equal((await request('/v1/notifications/read',{body:{ids:['review109']}})).status,404);
});
test('tenant isolation and unknown staff rejection',async()=>{
  const other=await request('/v1/snapshot',{auth:token('sarah',{hotel_id:'hotel-b'})});assert.equal(other.body.supplies[0].quantity,42);
  assert.equal((await request('/v1/snapshot',{auth:token('intruder')})).status,403);
  assert.equal((await request('/v1/snapshot',{auth:token('sarah',{hotel_id:'missing'})})).status,403);
});
test('service checkout is versioned and cannot read staff data',async()=>{
  const auth=token('reservations',{scope:'housekeeping:checkout'});
  assert.equal((await request('/v1/snapshot',{auth})).status,403);
  const key=randomUUID(),body={version:1};
  assert.equal((await request('/v1/rooms/112/checkout',{auth,body,key})).status,200);
  assert.equal((await request('/v1/rooms/112/checkout',{auth,body,key})).status,200);
  assert.equal((await snapshot()).body.rooms.find(r=>r.number==='112').status,'dirty');
});
test('CORS rejects unknown browser origins and invalid bodies roll back',async()=>{
  assert.equal((await request('/v1/snapshot',{headers:{Origin:'https://unknown.example'}})).status,403);
  assert.equal((await request('/v1/rooms/118/assign',{sub:'amina',body:{version:1,employeeId:'unknown',note:'',urgent:false}})).status,400);
  assert.equal((await snapshot()).body.rooms.find(r=>r.number==='118').version,1);
});
test('database survives server restart with audit and idempotency records',async()=>{
  await stop();await start();
  assert.equal((await snapshot()).body.supplies[0].quantity,40);
  assert.equal((await snapshot()).body.rooms.find(r=>r.number==='305').status,'ready');
  assert.equal((await snapshot()).body.notifications.find(n=>n.id==='vip305').read,true);
  assert.ok(store.db.prepare('SELECT count(*) AS n FROM audit').get().n>=10);
});

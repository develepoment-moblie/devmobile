// Temporary real HTTP server for the Dart-to-Node integration test.
import {generateKeyPairSync,sign} from 'node:crypto';
import {mkdirSync,writeFileSync} from 'node:fs';
import {Store} from '../store.mjs';
import {demoState} from '../seed.mjs';
import {createApi} from '../server.mjs';
const pair=generateKeyPairSync('rsa',{modulusLength:2048,publicKeyEncoding:{type:'spki',format:'pem'},privateKeyEncoding:{type:'pkcs8',format:'pem'}});
const store=new Store(':memory:');store.provision('bridge',demoState());
const server=createApi({store,publicKey:pair.publicKey,issuer:'bridge',audience:'housekeeping'});
const token=sub=>{
  const iat=Math.floor(Date.now()/1000),h=Buffer.from('{"alg":"RS256"}').toString('base64url'),p=Buffer.from(JSON.stringify({sub,hotel_id:'bridge',iss:'bridge',aud:'housekeeping',iat,exp:iat+600})).toString('base64url');
  return `${h}.${p}.${sign('RSA-SHA256',Buffer.from(`${h}.${p}`),pair.privateKey).toString('base64url')}`;
};
server.listen(0,'127.0.0.1',()=>{
  mkdirSync('.dev',{recursive:true});
  writeFileSync('.dev/bridge.json',JSON.stringify({url:`http://127.0.0.1:${server.address().port}`,amina:token('amina'),sarah:token('sarah')}),{mode:0o600});
  console.log('Isolated bridge test server ready (10 minute maximum lifetime).');
});
const close=()=>server.close(()=>{store.close();process.exit(0);});
process.on('SIGINT',close);process.on('SIGTERM',close);setTimeout(close,600000).unref();

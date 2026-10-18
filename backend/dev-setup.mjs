// Local demonstration credentials only. No registration or login endpoints.
import { generateKeyPairSync, sign } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { Store } from './store.mjs';
import { demoState } from './seed.mjs';
mkdirSync('.dev',{recursive:true});mkdirSync('data',{recursive:true});
if(!existsSync('.dev/private.pem')) {
  const pair=generateKeyPairSync('rsa',{modulusLength:2048,publicKeyEncoding:{type:'spki',format:'pem'},privateKeyEncoding:{type:'pkcs8',format:'pem'}});
  writeFileSync('.dev/private.pem',pair.privateKey,{mode:0o600});writeFileSync('.dev/public.pem',pair.publicKey);
}
const store=new Store('data/housekeeping.sqlite');store.provision('nova-demo',demoState());store.close();
const privateKey=readFileSync('.dev/private.pem'),iat=Math.floor(Date.now()/1000);
for(const sub of ['sarah','lina','youssef','amina']) {
  const h=Buffer.from(JSON.stringify({alg:'RS256',typ:'JWT'})).toString('base64url');
  const p=Buffer.from(JSON.stringify({sub,hotel_id:'nova-demo',iss:'nova-local-dev',aud:'nova-housekeeping',iat,exp:iat+86400})).toString('base64url');
  const token=`${h}.${p}.${sign('RSA-SHA256',Buffer.from(`${h}.${p}`),privateKey).toString('base64url')}`;
  writeFileSync(`.dev/${sub}.json`,JSON.stringify({HOUSEKEEPING_API_URL:'http://127.0.0.1:8086',HOUSEKEEPING_TOKEN:token},null,2),{mode:0o600});
}
console.log('Demo DB provisioned without resetting saved data. Private .dev/*.json run configurations refreshed for 24 hours.');

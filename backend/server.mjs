import { createServer } from 'node:http';
import { readFileSync, mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Store, ApiError } from './store.mjs';
import { authenticator } from './auth.mjs';

export function createApi({store, publicKey, issuer, audience, origins=[]}) {
  const authenticate=authenticator({publicKey,issuer,audience});
  return createServer(async(req,res)=>{
    const origin=req.headers.origin;
    res.setHeader('Cache-Control','no-store');res.setHeader('X-Content-Type-Options','nosniff');
    res.setHeader('Vary','Origin');
    const send=(status,data)=>{res.writeHead(status,{'Content-Type':'application/json; charset=utf-8'});res.end(JSON.stringify(data));};
    try {
      if(origin) {
        if(!origins.includes(origin)) throw new ApiError(403,'Origine non autorisée.');
        res.setHeader('Access-Control-Allow-Origin',origin);
        res.setHeader('Access-Control-Allow-Headers','Authorization, Content-Type, Idempotency-Key');
        res.setHeader('Access-Control-Allow-Methods','GET, POST, OPTIONS');
      }
      if(req.method==='OPTIONS') {res.writeHead(204);res.end();return;}
      const path=new URL(req.url,'http://localhost').pathname;
      const claims=authenticate(req.headers.authorization);
      if(req.method==='GET'&&path==='/v1/snapshot') return send(200,store.snapshot(claims));
      if(req.method!=='POST') throw new ApiError(404,'Route introuvable.');
      if(req.headers['content-type']?.split(';')[0]!=='application/json') throw new ApiError(415,'JSON requis.');
      const chunks=[];let size=0;
      for await(const chunk of req) {size+=chunk.length;if(size>16384) throw new ApiError(413,'Requête trop volumineuse.');chunks.push(chunk);}
      let body;try {body=JSON.parse(Buffer.concat(chunks).toString());} catch {throw new ApiError(400,'JSON invalide.');}
      if(!body||typeof body!=='object'||Array.isArray(body)) throw new ApiError(400,'Objet JSON requis.');
      store.mutate(claims,path,body,req.headers['idempotency-key']);
      send(200,{ok:true});
    } catch(error) {
      if(!(error instanceof ApiError)) console.error('API error:',error);
      if(!res.headersSent) send(error.status??500,{error:error.status?error.message:'Serveur indisponible. Réessayez.'});else res.end();
    }
  });
}

if(process.argv[1]&&resolve(process.argv[1])===fileURLToPath(import.meta.url)) {
  const dbPath=process.env.DB_PATH??'data/housekeeping.sqlite';mkdirSync(dirname(dbPath),{recursive:true});
  const publicKeyPath=process.env.JWT_PUBLIC_KEY;
  if(!publicKeyPath||!process.env.JWT_ISSUER||!process.env.JWT_AUDIENCE) throw new Error('Set JWT_PUBLIC_KEY, JWT_ISSUER, JWT_AUDIENCE. See backend/README.md');
  const store=new Store(dbPath);
  const server=createApi({store,publicKey:readFileSync(publicKeyPath),issuer:process.env.JWT_ISSUER,audience:process.env.JWT_AUDIENCE,origins:(process.env.CORS_ORIGINS??'').split(',').filter(Boolean)});
  server.requestTimeout=15000;server.headersTimeout=10000;
  server.listen(Number(process.env.PORT??8086),process.env.HOST??'127.0.0.1',()=>console.log(`Housekeeping API listening on ${process.env.HOST??'127.0.0.1'}:${process.env.PORT??8086}`));
  for(const signal of ['SIGINT','SIGTERM']) process.on(signal,()=>server.close(()=>{store.close();process.exit(0);}));
}

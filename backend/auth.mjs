import { verify, createPublicKey } from 'node:crypto';
import { ApiError } from './store.mjs';

export function authenticator({publicKey, issuer, audience}) {
  const key=createPublicKey(publicKey);
  if(key.asymmetricKeyType!=='rsa'||key.asymmetricKeyDetails.modulusLength<2048) throw new Error('RSA key >= 2048 bits required');
  return authorization => {
    try {
      if(!authorization?.startsWith('Bearer ')) throw new Error();
      const token=authorization.slice(7);
      if(token.length>8192) throw new Error();
      const parts=token.split('.');if(parts.length!==3) throw new Error();
      const [header,payload,signature]=parts;
      const h=JSON.parse(Buffer.from(header,'base64url'));
      if(h.alg!=='RS256'||h.crit!==undefined) throw new Error();
      if(!verify('RSA-SHA256',Buffer.from(`${header}.${payload}`),key,Buffer.from(signature,'base64url'))) throw new Error();
      const c=JSON.parse(Buffer.from(payload,'base64url')), now=Math.floor(Date.now()/1000);
      if(c.iss!==issuer||!(c.aud===audience||(Array.isArray(c.aud)&&c.aud.includes(audience)))||!Number.isInteger(c.exp)||c.exp<=now||!Number.isInteger(c.iat)||c.iat>now+30||c.exp<=c.iat||(c.nbf!==undefined&&(!Number.isInteger(c.nbf)||c.nbf>now))||typeof c.sub!=='string'||!c.sub||typeof c.hotel_id!=='string'||!c.hotel_id) throw new Error();
      return c;
    } catch { throw new ApiError(401,'Session absente ou expirée. Reconnectez-vous via le module utilisateur.'); }
  };
}

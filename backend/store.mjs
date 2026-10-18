import { DatabaseSync } from 'node:sqlite';
import { randomUUID } from 'node:crypto';

export class ApiError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}
const requireThat = (condition, status, message) => { if (!condition) throw new ApiError(status, message); };

export class Store {
  constructor(path) {
    this.db = new DatabaseSync(path);
    this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;
      CREATE TABLE IF NOT EXISTS hotels (id TEXT PRIMARY KEY, state TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS reads (hotel TEXT, actor TEXT, notification TEXT, PRIMARY KEY(hotel,actor,notification));
      CREATE TABLE IF NOT EXISTS operations (hotel TEXT, actor TEXT, key TEXT, fingerprint TEXT, PRIMARY KEY(hotel,actor,key));
      CREATE TABLE IF NOT EXISTS audit (id INTEGER PRIMARY KEY, hotel TEXT, actor TEXT, action TEXT, resource TEXT, at TEXT, detail TEXT);`);
  }
  provision(id, state) {
    this.db.prepare('INSERT OR IGNORE INTO hotels VALUES (?,?)').run(id, JSON.stringify(state));
  }
  state(hotel) {
    const row = this.db.prepare('SELECT state FROM hotels WHERE id=?').get(hotel);
    requireThat(row,403,'Hôtel non autorisé.');
    return JSON.parse(row.state);
  }
  principal(claims, state) {
    const staff = state.staff.find(s=>s.id===claims.sub);
    // Service identity is issued only by the trusted reservation server.
    if (!staff && claims.scope === 'housekeeping:checkout') return {id:claims.sub,name:claims.sub,role:'checkout-service'};
    requireThat(staff,403,'Personnel non autorisé.');
    return staff;
  }
  snapshot(claims) {
    const state = this.state(claims.hotel_id);
    const principal = this.principal(claims,state);
    requireThat(principal.role!=='checkout-service',403,'Compte de service sans accès au personnel.');
    const reads = new Set(this.db.prepare('SELECT notification FROM reads WHERE hotel=? AND actor=?').all(claims.hotel_id,claims.sub).map(r=>r.notification));
    return {...state, principal, notifications:state.notifications.filter(n=>n.audience==='all'||n.audience===principal.role||n.audience===principal.id).map(n=>({...n,read:reads.has(n.id)}))};
  }
  mutate(claims, path, body, key) {
    requireThat(typeof key==='string' && /^[a-zA-Z0-9_-]{16,100}$/.test(key),400,'Clé de requête manquante.');
    const hotel = claims.hotel_id;
    const fingerprint = JSON.stringify([path,body]);
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const state=this.state(hotel), actor=this.principal(claims,state);
      const old=this.db.prepare('SELECT fingerprint FROM operations WHERE hotel=? AND actor=? AND key=?').get(hotel,actor.id,key);
      if (old) {
        requireThat(old.fingerprint===fingerprint,409,'Cette clé correspond à une autre opération.');
        this.db.exec('COMMIT'); return;
      }
      const supervisor=()=>requireThat(actor.role==='supervisor',403,'Action réservée à la gouvernante.');
      const own=room=>requireThat(actor.role==='agent'&&room.employeeId===actor.id,403,'Vous pouvez modifier uniquement vos tâches attribuées.');
      const version=item=>requireThat(Number.isInteger(body.version)&&body.version===item.version,409,'Données modifiées sur un autre appareil. Actualisez puis réessayez.');
      const parts=path.split('/').filter(Boolean);
      let resource = parts[2] ?? 'notifications';
      if(parts[1]==='rooms' && parts.length===4) {
        const room=state.rooms.find(r=>r.number===parts[2]);
        requireThat(room,404,'Chambre introuvable.');
        const action=parts[3];
        if(action==='assign'||action==='approve') supervisor();
        else if(action==='checkout') requireThat(actor.role==='checkout-service'&&claims.scope==='housekeeping:checkout',403,'Le départ doit venir du module réservations.');
        else own(room);
        version(room);
        if(action==='assign') {
          requireThat(room.status==='dirty'&&['waiting','inProgress'].includes(room.cleaning),409,'Cette tâche ne peut plus être attribuée.');
          requireThat(state.staff.some(s=>s.id===body.employeeId&&s.role==='agent'),400,'Agent invalide.');
          requireThat(typeof body.note==='string'&&body.note.length<=200&&typeof body.urgent==='boolean',400,'Consignes invalides.');
          const changed=room.employeeId!==body.employeeId;
          room.employeeId=body.employeeId; room.note=body.note; room.urgent=body.urgent;
          if(changed) { room.cleaning='waiting'; room.checklist.fill(false); }
        } else if(action==='start') {
          requireThat(room.status==='dirty'&&room.cleaning==='waiting',409,'Nettoyage déjà commencé ou indisponible.'); room.cleaning='inProgress';
        } else if(action==='checklist') {
          requireThat(room.status==='dirty'&&room.cleaning==='inProgress',409,'Nettoyage non actif.');
          requireThat(Number.isInteger(body.index)&&body.index>=0&&body.index<4&&typeof body.value==='boolean',400,'Contrôle invalide.');
          room.checklist[body.index]=body.value;
        } else if(action==='submit') {
          requireThat(room.status==='dirty'&&room.cleaning==='inProgress'&&room.checklist.every(Boolean),409,'Complétez les quatre contrôles.');
          room.cleaning='review';
          state.notifications.unshift({id:randomUUID(),title:'Nettoyage à valider',message:`Chambre ${room.number} prête pour inspection.`,roomNumber:room.number,audience:'supervisor'});
        } else if(action==='approve') {
          requireThat(room.status==='dirty'&&room.cleaning==='review',409,'Aucun nettoyage à valider.');
          room.cleaning='completed'; room.status='ready';room.urgent=false;room.approvedBy=actor.name;
        } else if(action==='checkout') {
          requireThat(room.status==='occupied',409,'La chambre n’est pas occupée.');
          Object.assign(room,{status:'dirty',cleaning:'waiting',employeeId:null,note:'Le client vient de quitter la chambre',urgent:false,approvedBy:null});room.checklist.fill(false);
          state.notifications.unshift({id:randomUUID(),title:'Départ client',message:`Chambre ${room.number} à nettoyer.`,roomNumber:room.number,audience:'all'});
        } else throw new ApiError(404,'Action inconnue.');
        room.version++;
        const labels={assign:'Attribution',start:'Nettoyage démarré',checklist:'Contrôle enregistré',submit:'Nettoyage envoyé pour validation',approve:'Nettoyage validé · chambre libre',checkout:'Départ enregistré'};
        room.history.push(`${labels[action]} · ${actor.name} · ${new Date().toISOString()}`);
      } else if(parts[1]==='supplies'&&parts.length===4&&parts[3]==='movement') {
        supervisor();
        const supply=state.supplies.find(s=>s.id===parts[2]);requireThat(supply,404,'Produit introuvable.');version(supply);
        requireThat(Number.isInteger(body.delta)&&body.delta!==0&&Math.abs(body.delta)<=100000,400,'Quantité invalide.');
        requireThat(supply.quantity+body.delta>=0&&supply.quantity+body.delta<=1000000,409,'Stock insuffisant ou limite atteinte.');
        supply.quantity+=body.delta;supply.version++;
      } else if(path==='/v1/notifications/read') {
        requireThat(actor.role!=='checkout-service',403,'Action non autorisée.');
        requireThat(Array.isArray(body.ids)&&body.ids.length<=1000&&body.ids.every(id=>typeof id==='string'),400,'Notifications invalides.');
        const visible=this.snapshot(claims).notifications;
        for(const id of body.ids) {
          requireThat(visible.some(n=>n.id===id),404,'Notification introuvable.');
          this.db.prepare('INSERT OR IGNORE INTO reads VALUES (?,?,?)').run(hotel,actor.id,id);
        }
      } else throw new ApiError(404,'Route introuvable.');
      this.db.prepare('UPDATE hotels SET state=? WHERE id=?').run(JSON.stringify(state),hotel);
      this.db.prepare('INSERT INTO operations VALUES (?,?,?,?)').run(hotel,actor.id,key,fingerprint);
      this.db.prepare('INSERT INTO audit (hotel,actor,action,resource,at,detail) VALUES (?,?,?,?,?,?)').run(hotel,actor.id,path,resource,new Date().toISOString(),JSON.stringify(body));
      this.db.exec('COMMIT');
    } catch(error) { this.db.exec('ROLLBACK'); throw error; }
  }
  close() { this.db.close(); }
}

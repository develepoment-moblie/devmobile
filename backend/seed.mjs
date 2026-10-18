// Test fixtures only; production hotels are provisioned separately.
export function demoState() {
  const room = (number, extra = {}) => ({number, category: 'Chambre Deluxe', status: 'dirty', cleaning: 'waiting', employeeId: null, note: '', urgent: false, checklist: [false,false,false,false], history: ['Chambre ajoutée au planning du matin'], version: 1, ...extra});
  return {
    staff: [{id:'sarah',name:'Sarah',role:'agent'}, {id:'lina',name:'Lina',role:'agent'}, {id:'youssef',name:'Youssef',role:'agent'}, {id:'amina',name:'Amina',role:'supervisor'}],
    rooms: [room('305',{note:'Départ VIP · avant 12h',urgent:true}), room('214',{cleaning:'inProgress',employeeId:'sarah'}),room('118',{note:'Départ à 10:30'}),room('402',{status:'ready',cleaning:'completed',approvedBy:'Amina'}), ...['101','203','306','410'].map(n=>room(n)),room('207',{cleaning:'inProgress',employeeId:'lina'}),room('311',{cleaning:'inProgress',employeeId:'youssef'}), ...[['109','sarah'],['208','lina'],['404','sarah']].map(([n,id])=>room(n,{cleaning:'review',employeeId:id,checklist:[true,true,true,true]})),room('112',{status:'occupied',note:'Départ prévu à 11:00'}),room('224',{status:'maintenance',note:'Télévision sans signal'}),room('301',{status:'ready',cleaning:'completed',approvedBy:'Amina'})],
    supplies: [['sheets','Draps propres',42,'pièces',15],['towels','Serviettes',68,'pièces',20],['cases','Taies d’oreiller',36,'pièces',15],['cleaner','Nettoyant multi-surfaces',4,'litres',5],['soap','Savon et gel douche',84,'unités',25]].map(([id,name,quantity,unit,minimum])=>({id,name,quantity,unit,minimum,version:1})),
    notifications: [{id:'vip305',title:'Départ VIP',message:'Chambre 305 à préparer avant 12h.',roomNumber:'305',audience:'all'}, ...['109','208','404'].map(n=>({id:`review${n}`,title:'Nettoyage à valider',message:`Chambre ${n} prête pour inspection.`,roomNumber:n,audience:'supervisor'}))]
  };
}

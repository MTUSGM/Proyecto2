export const factions = {
 imperio: { name: 'Imperio', title: 'El orden es eterno.', bonus: '+15% de poder defensivo', color: '#d6b579', emblem: '✦', description: 'Fortifica tu mundo. Que la frontera se quiebre antes que tus defensas.' },
 orkos: { name: 'Orkos', title: 'La guerra nos llama.', bonus: '−20% al coste de tropas · +10% de ataque', color: '#9dbb83', emblem: '⟁', description: 'Levanta un ejército imparable y conquista la iniciativa en cada batalla.' },
 herejes: { name: 'Herejes', title: 'Más allá del orden.', bonus: '+50% de botín por victoria', color: '#b99bd3', emblem: '✧', description: 'Abraza el caos. Cada victoria alimenta el tesoro de tu facción.' }
};
export const buildings = [
 {id:'mine',name:'Mina orbital',icon:'◇',desc:'Extrae minerales para expandir tu imperio.',rate:120,resource:'minerales'},
 {id:'reactor',name:'Reactor de plasma',icon:'ϟ',desc:'Energía para tecnología y expediciones.',rate:90,resource:'energía'},
 {id:'farm',name:'Complejo de suministros',icon:'▦',desc:'Mantén a tus tropas listas para combatir.',rate:75,resource:'suministros'},
 {id:'defense',name:'Bastión planetario',icon:'⛨',desc:'+100 de defensa por nivel.'},
 {id:'tech',name:'Laboratorio militar',icon:'⌬',desc:'+15% al poder de las tropas por nivel adicional.'}
];
export const nests=[{id:1,name:'Nido Caronte',power:250,label:'Exploración',x:26,y:40},{id:2,name:'Colmena Vesper',power:750,label:'Amenaza media',x:66,y:28},{id:3,name:'Leviatán IX',power:1800,label:'Amenaza extrema',x:75,y:72}];
export const fmt = n => new Intl.NumberFormat('es-EC',{maximumFractionDigits:0}).format(n??0);
export function attackPower(troops, tech, faction){return troops*10*(1+(tech-1)*.15)*(faction==='orkos'?1.1:1)+Math.ceil(troops/30)*20;}
export function recruitCost(n,faction){const factor=faction==='orkos'?.8:1; return {minerals:n*10*factor,supplies:n*8*factor};}
export function escapeHTML(value){return String(value??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));}

export const unitTypes=['ranged','melee','tank'];
export const unitLabels={ranged:'A distancia',melee:'Cuerpo a cuerpo',tank:'Tanques'};
export const emptyUnits=()=>({ranged:0,melee:0,tank:0});
export const unitCount=units=>unitTypes.reduce((n,k)=>n+Number(units?.[k]||0),0);
export const cargoUsed=(units,catalog)=>unitTypes.reduce((n,k)=>n+(units[k]||0)*catalog[k].space,0);
export function typedPower(units,catalog,tech,faction,defending=false,bastion=0){
 const base=unitTypes.reduce((n,k)=>n+(units[k]||0)*catalog[k][defending?'defense':'attack'],0)*(1+(tech-1)*.15);
 return defending?(base+bastion*100)*(faction==='imperio'?1.15:1):base*(faction==='orkos'?1.1:1)+Math.ceil(cargoUsed(units,catalog)/30)*20;
}
export function typedCost(n,type,catalog,faction){const u=catalog[type],factor=faction==='orkos'?.8:1;return {minerals:n*u.minerals*factor,energy:n*u.energy*factor,supplies:n*u.supplies*factor};}

export const shipTypes=['transport','combat'];
export const emptyFleet=()=>({transport:0,combat:0});
export const fleetCapacity=f=>(f.transport||0)*30+(f.combat||0)*10;
export const orbitalPower=f=>(f.transport||0)*12+(f.combat||0)*120;
export function tacticalPower(units,catalog,tech,defending,opponent){
 const total=(opponent.ranged||0)+(opponent.melee||0)+5*(opponent.tank||0);
 const good={ranged:'melee',melee:'tank',tank:'ranged'},bad={ranged:'tank',melee:'ranged',tank:'melee'};
 return unitTypes.reduce((n,k)=>{const g=good[k],b=bad[k],mult=total?1+.5*(opponent[g]||0)*(g==='tank'?5:1)/total-.25*(opponent[b]||0)*(b==='tank'?5:1)/total:1;return n+(units[k]||0)*catalog[k][defending?'defense':'attack']*mult;},0)*(1+(tech-1)*.15);
}
export function expeditionEstimate(units,fleet,catalog,faction,tech,enemy,enemyCatalog){
 const orbital=orbitalPower(fleet),orbitalDefense=enemy.orbital_power,rate=Math.min(.2,.15*orbitalDefense/Math.max(1,orbital));
 const landed=Object.fromEntries(unitTypes.map(k=>[k,Math.max(0,units[k]-Math.ceil(units[k]*rate*(1-catalog[k].armor/100)))]));
 const base=tacticalPower(landed,catalog,tech,false,enemy.ground)*(faction==='orkos'?1.1:1);
 const support=Math.min(base*.25,fleet.transport+fleet.combat*6);
 const defense=(tacticalPower(enemy.ground,enemyCatalog,enemy.tech,true,landed)+enemy.defense*100)*(enemy.faction==='imperio'?1.15:1);
 const repairs=Math.ceil(Math.min(2,orbitalDefense/Math.max(1,orbital))*(fleet.transport+fleet.combat)*10);
 return {orbital,orbitalDefense,attack:base+support,defense,support,landed,energy:fleet.transport*25+fleet.combat*70+repairs,supplies:unitTypes.reduce((n,k)=>n+units[k]*catalog[k].upkeep,0)+fleet.transport*5+fleet.combat*15,repairs};
}

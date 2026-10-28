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

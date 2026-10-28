import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';import vm from 'node:vm';
import * as rules from '../src/rules.js';
const strategy=JSON.parse(fs.readFileSync(new URL('../src/strategy.json',import.meta.url)));
const source=fs.readFileSync(new URL('../src/main.js',import.meta.url),'utf8').replace(/^import .*;\n/gm,'').replaceAll('import.meta.env.VITE_SUPABASE_URL',"'https://example.supabase.co'").replaceAll('import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY',"'test-publishable'");
test('client renders every game page with two ship classes and typed NPC scouting',async()=>{
 const handlers={},app={innerHTML:'',addEventListener:(k,f)=>handlers[k]=f},toast={};
 const empire={ground:{ranged:40,melee:0,tank:0},embarked:{ranged:0,melee:0,tank:0},fleet:{transport:0,combat:0},transports:2,warships:0,ships:2,orbital:0,mine:1,reactor:1,farm:1,defense:1,tech:1,minerals:1200,energy:900,supplies:800,loot:0};
 const state={commander:{id:'one',name:'QA',planet:'QA World',faction:'imperio',elo:1000,wins:0,battles:0},empire,ranking:[],reports:[],unit_catalog:strategy.units.imperio,all_units:strategy.units,ship_catalog:strategy.ships,npc_catalog:strategy.npcs};
 const db={auth:{onAuthStateChange(){},getSession:async()=>({data:{session:{user:{id:'one'}}}})},rpc:async()=>({data:state})};
 vm.runInNewContext(source,{...rules,esc:rules.escapeHTML,createClient:()=>db,document:{querySelector:s=>s==='#app'?app:s==='#toast'?toast:null,addEventListener(){},activeElement:null},window:{scrollTo(){}},location:{origin:'https://example.com'},setInterval(){},setTimeout,clearTimeout,Intl,Date,console});
 await new Promise(resolve=>setTimeout(resolve,10));
 assert.match(app.innerHTML,/Centro de mando/);
 const navigate=async page=>handlers.click({target:{closest:()=>({dataset:{page}})}});
 await navigate('army');assert.match(app.innerHTML,/Fragata de combate/);assert.match(app.innerHTML,/Construir transporte/);assert.match(app.innerHTML,/Construir fragata/);
 await navigate('planet');assert.match(app.innerHTML,/Baterías orbitales/);assert.doesNotMatch(app.innerHTML,/undefined|NaN/);
 await navigate('galaxy');assert.match(app.innerHTML,/Termagante: 20/);assert.match(app.innerHTML,/Hormagante: 10/);assert.match(app.innerHTML,/ship_combat/);assert.match(app.innerHTML,/Plazas ocupadas/);assert.doesNotMatch(app.innerHTML,/undefined|NaN/);
 await navigate('reports');assert.match(app.innerHTML,/Registro de operaciones/);
 await navigate('ranking');assert.match(app.innerHTML,/Comandantes de la frontera/);
});

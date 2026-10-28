import test from 'node:test';import assert from 'node:assert/strict';import fs from 'node:fs';
import {fleetCapacity,orbitalPower,tacticalPower,expeditionEstimate} from '../src/rules.js';
const s=JSON.parse(fs.readFileSync(new URL('../src/strategy.json',import.meta.url)));
test('transports carry more, combat ships shoot harder',()=>{assert.equal(fleetCapacity({transport:1,combat:1}),40);assert.equal(orbitalPower({transport:1,combat:1}),132);});
test('composition changes outcome at identical unit count',()=>{const u={ranged:10,melee:0,tank:0};assert.equal(tacticalPower(u,s.units.imperio,1,false,{ranged:0,melee:10,tank:0}),150);assert.equal(tacticalPower(u,s.units.imperio,1,false,{ranged:0,melee:0,tank:2}),75);});
test('NPCs have distinct armies and orbital barriers',()=>{assert.equal(s.npcs[0].ground.tank,0);assert.equal(s.npcs[2].ground.tank,10);assert.ok(s.npcs[2].orbital_power>s.npcs[0].orbital_power);});
test('overloading escorts costs fuel without unlimited bombardment',()=>{const r=expeditionEstimate({ranged:1,melee:0,tank:0},{transport:0,combat:100},s.units.imperio,'imperio',1,s.npcs[0],s.units.tiranidos);assert.ok(r.energy>=7000);assert.ok(r.support<=r.attack*.25);});

import test from 'node:test';
import assert from 'node:assert/strict';
import {attackPower,recruitCost,escapeHTML} from '../src/rules.js';
test('transport contributes once per occupied ship',()=>{assert.equal(attackPower(30,1,'imperio'),320);assert.equal(attackPower(31,1,'imperio'),350);});
test('Ork faction differentiates recruitment and offense',()=>{assert.deepEqual(recruitCost(10,'orkos'),{minerals:80,supplies:64});assert.ok(Math.abs(attackPower(40,1,'orkos')-480)<1e-9);});
test('research improves troops, not transport bonus',()=>assert.ok(Math.abs(attackPower(40,2,'imperio')-500)<1e-9));
test('commander and planet names cannot inject HTML',()=>assert.equal(escapeHTML('<img src=x onerror="alert(1)">'), '&lt;img src=x onerror=&quot;alert(1)&quot;&gt;'));

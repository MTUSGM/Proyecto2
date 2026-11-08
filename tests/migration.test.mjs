import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs/promises';
import {PGlite} from '@electric-sql/pglite';

test('production migration preserves games, halves timers and enforces notification ownership',async()=>{
 const db=new PGlite();
 try{
 await db.exec(`create role anon; create role authenticated; create schema auth;
 create table auth.users(id uuid primary key,email text);
 create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
 grant usage on schema auth to authenticated;grant execute on function auth.uid() to authenticated;
 create publication supabase_realtime;`);
 for(const path of ['supabase/schema.sql','supabase/units_upgrade.sql','supabase/orbital_upgrade.sql'])await db.exec(await fs.readFile(path,'utf8'));
 await db.exec(await fs.readFile('tests/orbital.sql','utf8'));
 const a='00000000-0000-4000-8000-000000000101',b='00000000-0000-4000-8000-000000000102';
 await db.exec(`insert into auth.users values('${a}','a@example.test'),('${b}','b@example.test');begin;
 select set_config('request.jwt.claim.sub','${a}',true);select public.game('create','{"name":"Alpha QA","planet":"Alpha QA","faction":"imperio"}');
 select set_config('request.jwt.claim.sub','${b}',true);select public.game('create','{"name":"Beta QA","planet":"Beta QA","faction":"orkos"}');
 update public.empire set minerals=100,energy=100,supplies=100,collected_at=now()-interval '1 hour',shield_until=now()+interval '8 minutes',attack_at=now()-interval '20 seconds';`);
 await db.exec(await fs.readFile('supabase/migrations/20261108163806_realtime_auth_speed.sql','utf8'));
 let rows=(await db.query(`select minerals,energy,supplies,extract(epoch from shield_until-now()) shield,extract(epoch from now()-attack_at) cooldown_age from public.empire`)).rows;
 for(const row of rows){assert.equal(Number(row.minerals),220);assert.equal(Number(row.energy),190);assert.equal(Number(row.supplies),175);assert.equal(Number(row.shield),240);assert.equal(Number(row.cooldown_age),10);}
 await db.exec(`update public.empire set shield_until=now()-interval '1 hour',attack_at=null,minerals=10000,energy=10000,supplies=10000;
 select set_config('request.jwt.claim.sub','${a}',true);
 select public.game('embark','{"units":{"ranged":10,"melee":0,"tank":0},"fleet":{"transport":1,"combat":0}}');`);
 const attack={target:b,request_id:'00000000-0000-4000-8000-000000000111'};
 await db.query("select public.game('attack',$1::jsonb)",[JSON.stringify(attack)]);
 await db.exec(`do $$ begin assert (select count(*) from public.attack_notifications)=1;assert (select sum(elo) from public.commanders)=2000; end $$;`);
 await db.exec(`savepoint duplicate;`);
 await assert.rejects(db.query("select public.game('attack',$1::jsonb)",[JSON.stringify(attack)]),/ya fue procesada/);
 await db.exec('rollback to duplicate;');
 await db.exec(`update public.empire set attack_at=now()-interval '29 seconds' where id='${a}';savepoint cooldown;`);
 await assert.rejects(db.query("select public.game('attack','{\"npc\":1}')"),/Espera 30 segundos/);await db.exec('rollback to cooldown;');
 await db.exec(`update public.empire set attack_at=now()-interval '30 seconds' where id='${a}';select public.game('attack','{"npc":1}');`);

 await db.exec(`select set_config('request.jwt.claim.sub','${b}',true);set local role authenticated;`);
 let r=(await db.query("select public.game('state') as s")).rows[0].s;
 assert.equal(r.notifications.length,1);assert.equal(r.notifications[0].attacker,a);assert.equal(r.timing.attack_cooldown_seconds,30);
 assert.equal((await db.query('select * from public.empire')).rows.length,1);
 await db.exec('savepoint protected;');await assert.rejects(db.exec('update public.empire set minerals=99999'),/permission denied/);await db.exec('rollback to protected;');
 await db.exec('savepoint protected_notice;');await assert.rejects(db.exec(`update public.attack_notifications set recipient='${a}'`),/permission denied/);await db.exec('rollback to protected_notice;');
 await db.exec('update public.attack_notifications set read_at=now();reset role;');
 r=(await db.query("select public.game('state') as s")).rows[0].s;assert.equal(r.notifications.length,0);
 await db.exec(`select set_config('request.jwt.claim.sub','${a}',true);set local role authenticated;`);
 assert.equal((await db.query('select * from public.attack_notifications')).rows.length,0);
 await db.exec(`reset role;update public.empire set minerals=0,energy=0,supplies=0,collected_at=now()-interval '1 hour' where id='${a}';`);
 r=(await db.query("select public.game('state') as s")).rows[0].s;
 assert.equal(r.empire.minerals,240);assert.equal(r.empire.energy,180);assert.equal(r.empire.supplies,150);
 assert.equal(Number((await db.query(`select minerals from public.empire where id='${a}'`)).rows[0].minerals),0,'state reads must not write or emit more changes');
 await db.exec('rollback;');
 }finally{await db.close();}
});

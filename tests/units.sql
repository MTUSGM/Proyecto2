-- Run in a transaction and roll back. Fixtures never affect player armies.
insert into auth.users(id,email) values ('00000000-0000-4000-8000-000000000011','units-qa1@example.invalid'),('00000000-0000-4000-8000-000000000012','units-qa2@example.invalid');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000011',true);
select public.game('create','{"name":"Units QA One","planet":"Units QA One","faction":"imperio"}') is not null;
select public.game('recruit','{"unit":"melee","quantity":10}') is not null;
select public.game('recruit','{"unit":"tank","quantity":2}') is not null;
select public.game('embark','{"units":{"ranged":10,"melee":5,"tank":2}}') is not null;
do $$ declare e public.empire; before_state jsonb; r jsonb; begin
 select * into e from public.empire where id=auth.uid();
 assert e.ground='{"ranged":30,"melee":5,"tank":0}'::jsonb,'Ground split';
 assert e.embarked='{"ranged":10,"melee":5,"tank":2}'::jsonb,'Persistent fleet';
 assert e.troops=52,'Conservation';
 assert e.minerals=760 and e.energy=770 and e.supplies=620,'Typed recruitment prices';
 before_state:=to_jsonb(e);
 begin perform public.game('embark','{"units":{"ranged":40,"melee":10,"tank":3}}'); raise exception 'test: allowed unavailable tanks'; exception when others then if sqlerrm like 'test:%' then raise; end if; end;
 begin perform public.game('embark','{"units":{"ranged":-1,"melee":0,"tank":0}}'); raise exception 'test: negative count'; exception when others then if sqlerrm like 'test:%' then raise; end if; end;
 begin perform public.game('embark','{"units":{"ranged":1.5,"melee":0,"tank":0}}'); raise exception 'test: fractional count'; exception when others then if sqlerrm like 'test:%' then raise; end if; end;
 begin perform public.game('embark','{"units":{"ranged":1,"melee":0,"tank":0,"fake":3}}'); raise exception 'test: unknown unit'; exception when others then if sqlerrm like 'test:%' then raise; end if; end;
 assert (select to_jsonb(x) from public.empire x where id=auth.uid())=before_state,'Failed embark must be atomic';
 r:=public.game('attack','{"npc":1}');
 assert r->'last_battle'->'sent_units'='{"ranged":10,"melee":5,"tank":2}'::jsonb,'Report composition';
 assert r->'empire'->'ground'=before_state->'ground','Attack never consumes ground units';
 assert (r->'commander'->>'elo')::int=1000,'NPC never changes Elo';
 assert (r->'empire'->>'troops')::int=52-(r->'last_battle'->>'lost')::int,'Casualties reconcile';
 perform public.game('embark','{"units":{"ranged":0,"melee":0,"tank":0}}');
 assert (select embarked from public.empire where id=auth.uid())='{"ranged":0,"melee":0,"tank":0}'::jsonb,'Disembark';
end $$;
-- A full transport: exactly 12 tanks occupy 60 spaces. Overflow is rejected.
update public.empire set ground='{"ranged":40,"melee":20,"tank":13}',embarked='{"ranged":0,"melee":0,"tank":0}',troops=73,attack_at=null where id=auth.uid();
select public.game('embark','{"units":{"ranged":0,"melee":0,"tank":12}}') is not null;
do $$ begin
 begin perform public.game('embark','{"units":{"ranged":1,"melee":0,"tank":12}}'); raise exception 'test: capacity overflow'; exception when others then if sqlerrm like 'test:%' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000012',true);
select public.game('create','{"name":"Units QA Two","planet":"Units QA Two","faction":"orkos"}') is not null;
select public.game('embark','{"units":{"ranged":40,"melee":0,"tank":0}}') is not null;
update public.empire set shield_until=now()-interval '1 hour' where id=auth.uid();
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000011',true);
do $$ declare r jsonb; begin
 r:=public.game('attack','{"target":"00000000-0000-4000-8000-000000000012"}');
 assert (r->'last_battle'->>'defense_power')::int=100,'Embarked defenders contribute no defense, nor do ships';
 assert (select embarked from public.empire where id='00000000-0000-4000-8000-000000000012')='{"ranged":40,"melee":0,"tank":0}'::jsonb,'Embarked defenders take no casualties';
 assert (select sum(elo) from public.commanders where id in ('00000000-0000-4000-8000-000000000011','00000000-0000-4000-8000-000000000012'))=2000,'Elo conservation';
 assert (r->'last_battle'->'losses'->>'tank')::int=1,'Armor reduces tank casualties';
end $$;
set local role authenticated;
do $$ begin
 assert (select count(*) from public.empire)=1,'RLS isolation';
 begin update public.empire set embarked='{"ranged":999,"melee":0,"tank":0}'; raise exception 'test: direct mutation'; exception when insufficient_privilege then null; end;
 assert public.game('state')->'unit_catalog'->'tank'->>'name'='Tanque Bastión','Authenticated state returns catalogue';
end $$;
reset role;
select 'PASS: typed recruitment, costs, persistence, conservation, capacity, invalid inputs, rollback, disembark, PvE, PvP, ground-only defense, armor, Elo, RLS' as result;

begin;
insert into auth.users(id,email) values ('00000000-0000-4000-8000-000000000021','orbital-one@example.invalid'),('00000000-0000-4000-8000-000000000022','orbital-two@example.invalid');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000021',true);
select public.game('create','{"name":"Orbital QA One","planet":"Orbital QA One","faction":"imperio"}') is not null;
select public.game('ship','{"type":"combat"}') is not null;
do $$ declare e public.empire; r jsonb; before_state jsonb; begin
 select * into e from public.empire where id=auth.uid();
 assert e.transports=2 and e.warships=1 and e.ships=3,'Ship types and total';
 assert e.minerals=600 and e.energy=500 and e.supplies=700,'Combat ship price';
 assert private.tactical_power('{"ranged":10,"melee":0,"tank":0}','imperio',1,false,'{"ranged":0,"melee":10,"tank":0}')=150,'Ranged counters melee';
 assert private.tactical_power('{"ranged":10,"melee":0,"tank":0}','imperio',1,false,'{"ranged":0,"melee":0,"tank":2}')=75,'Tanks resist ranged';
 assert private.tactical_power('{"ranged":0,"melee":10,"tank":0}','imperio',1,false,'{"ranged":0,"melee":0,"tank":2}')=225,'Melee demolition counters tanks';
 before_state:=to_jsonb(e);
 begin perform public.game('embark','{"units":{"ranged":20,"melee":0,"tank":0},"fleet":{"transport":0,"combat":1}}'); raise exception 'test: combat capacity'; exception when others then if sqlerrm like 'test:%' then raise; end if; end;
 begin perform public.game('embark','{"units":{"ranged":0,"melee":0,"tank":0},"fleet":{"transport":0,"combat":2}}'); raise exception 'test: unavailable ship'; exception when others then if sqlerrm like 'test:%' then raise; end if; end;
 begin perform public.game('embark','{"units":{"ranged":0,"melee":0,"tank":0},"fleet":{"transport":-1,"combat":0}}'); raise exception 'test: negative ships'; exception when others then if sqlerrm like 'test:%' then raise; end if; end;
 assert (select to_jsonb(x) from public.empire x where id=auth.uid())=before_state,'Failed composition atomic';
 perform public.game('embark','{"units":{"ranged":20,"melee":0,"tank":0},"fleet":{"transport":1,"combat":0}}');
 r:=public.game('attack','{"npc":3}');
 assert (r->'last_battle'->>'orbital_won')::boolean=false,'Weak fleet fails orbital phase';
 assert (r->'last_battle'->>'ground_fought')::boolean=false,'No unauthorized landing';
 assert (r->'last_battle'->>'defender_lost')::int=0,'No ground losses without landing';
 assert (r->'last_battle'->>'reward')::int=0,'No reward for failed orbit';
 assert r->'last_battle'->'defender_units'->>'tank'='10','NPC Carnifex composition';
 assert (r->'empire'->'ground'->>'ranged')::int=20,'Home garrison untouched';
 assert (r->'empire'->>'ships')::int=3,'Ships return';
end $$;
update public.empire set minerals=10000,energy=10000,supplies=10000,warships=10,transports=2,ships=12,tech=5,ground='{"ranged":80,"melee":60,"tank":10}',embarked='{"ranged":0,"melee":0,"tank":0}',fleet='{"transport":0,"combat":0}',troops=150,attack_at=null where id=auth.uid();
select public.game('embark','{"units":{"ranged":40,"melee":40,"tank":10},"fleet":{"transport":2,"combat":10}}') is not null;
do $$ declare r jsonb; begin
 r:=public.game('attack','{"npc":1}');
 assert (r->'last_battle'->>'orbital_won')::boolean,'Strong fleet clears orbit';
 assert (r->'last_battle'->>'won')::boolean,'Strong army wins on ground';
 assert (r->'last_battle'->>'defender_lost')::int>0,'NPC typed losses';
 assert (r->'commander'->>'elo')::int=1000,'NPC Elo unchanged';
 assert (r->'last_battle'->>'support')::numeric<=(r->'last_battle'->>'attack_power')::numeric*.25,'Naval support bounded';
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000022',true);
select public.game('create','{"name":"Orbital QA Two","planet":"Orbital QA Two","faction":"orkos"}') is not null;
select public.game('upgrade','{"building":"orbital"}') is not null;
do $$ declare r jsonb; begin
 r:=public.game('state');
 assert (r->'empire'->>'orbital')::int=1,'Orbital upgrade';
 assert exists(select from jsonb_array_elements(r->'ranking') x where x->>'id'=auth.uid()::text and (x->>'orbital_power')::int=104),'Batteries plus reserve ships';
 perform public.game('embark','{"units":{"ranged":40,"melee":0,"tank":0},"fleet":{"transport":2,"combat":0}}');
 r:=public.game('state');
 assert exists(select from jsonb_array_elements(r->'ranking') x where x->>'id'=auth.uid()::text and (x->>'orbital_power')::int=80),'Assigned ships excluded from home defense';
end $$;
update public.empire set shield_until=now()-interval '1 hour',orbital=1000 where false;
-- Force a high orbital barrier using reserve warships, within normal constraints.
update public.empire set warships=100,ships=102,shield_until=now()-interval '1 hour' where id=auth.uid();
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000021',true);
update public.empire set attack_at=null where id=auth.uid();
do $$ declare r jsonb; begin
 r:=public.game('attack','{"target":"00000000-0000-4000-8000-000000000022"}');
 assert not (r->'last_battle'->>'orbital_won')::boolean,'PvP orbital barrier';
 assert (select embarked->>'ranged' from public.empire where id='00000000-0000-4000-8000-000000000022')='40','Embarked defender protected from ground losses';
 assert (select sum(elo) from public.commanders where id in ('00000000-0000-4000-8000-000000000021','00000000-0000-4000-8000-000000000022'))=2000,'PvP Elo conservation';
end $$;
set local role authenticated;
do $$ begin
 assert public.game('state')->'ship_catalog'->'combat'->>'capacity'='10','Catalog API';
 assert jsonb_array_length(public.game('state')->'npc_catalog')=3,'NPC API';
 begin update public.empire set warships=10000; raise exception 'test: direct write'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'PASS: counters, ship construction, capacity, ownership, atomicity, orbital failure/success, NPC armies, casualties, costs, home reserve defense, PvP, Elo, authenticated API and RLS' as result;
rollback;

begin;
insert into auth.users(id,email) values ('00000000-0000-4000-8000-000000000001','qa-one@example.invalid'),('00000000-0000-4000-8000-000000000002','qa-two@example.invalid');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select public.game('create','{"name":"QA Alpha","planet":"Test Alpha","faction":"orkos"}') is not null as create_pass;
select public.game('recruit','{"quantity":10}') is not null as recruit_pass;
do $$ begin
 if not exists(select from public.empire where id='00000000-0000-4000-8000-000000000001' and troops=50 and minerals between 1119 and 1121) then raise exception 'Recruit calculation failed'; end if;
 begin perform public.game('recruit','{"quantity":-1}'); raise exception 'Accepted negative recruitment'; exception when others then if sqlerrm='Accepted negative recruitment' then raise; end if; end;
 begin perform public.game('attack','{"npc":1,"troops":999}'); raise exception 'Accepted transport overflow'; exception when others then if sqlerrm='Accepted transport overflow' then raise; end if; end;
end $$;
select public.game('upgrade','{"building":"tech"}') is not null as upgrade_pass;
select public.game('ship') is not null as ship_pass;
select public.game('attack','{"npc":1,"troops":40}') -> 'last_battle' as npc_report;
do $$ begin
 if not exists(select from public.commanders where id='00000000-0000-4000-8000-000000000001' and elo=1000 and wins=1) then raise exception 'NPC Elo or win failed'; end if;
 begin perform public.game('attack','{"npc":1,"troops":20}'); raise exception 'Cooldown failed'; exception when others then if sqlerrm='Cooldown failed' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
select public.game('create','{"name":"QA Beta","planet":"Test Beta","faction":"imperio"}') is not null as second_create_pass;
update public.empire set shield_until=now()-interval '1 hour',attack_at=null;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select public.game('attack','{"target":"00000000-0000-4000-8000-000000000002","troops":40}') -> 'last_battle' as pvp_report;
do $$ begin
 if (select sum(elo) from public.commanders where id in ('00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002'))<>2000 then raise exception 'Elo conservation failed'; end if;
 if (select count(*) from public.empire where id in ('00000000-0000-4000-8000-000000000001','00000000-0000-4000-8000-000000000002'))<>2 then raise exception 'Planet permanence failed'; end if;
end $$;
update public.empire set collected_at=now()-interval '48 hours',minerals=0,energy=0,supplies=0 where id='00000000-0000-4000-8000-000000000001';
select public.game('state') is not null as offline_pass;
do $$ begin
 if not exists(select from public.empire where id='00000000-0000-4000-8000-000000000001' and minerals=2880 and energy=2160 and supplies=1800) then raise exception 'Offline cap failed'; end if;
end $$;
set local role authenticated;
do $$ begin
 if (select count(*) from public.empire)<>1 then raise exception 'RLS ownership failed'; end if;
 begin update public.empire set minerals=99999; raise exception 'Direct mutation permitted'; exception when insufficient_privilege then null; end;
 if public.game('state')->'commander'->>'name'<>'QA Alpha' then raise exception 'Authenticated RPC failed'; end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
 begin perform private.game('state'); raise exception 'Missing auth permitted'; exception when others then if sqlerrm='Missing auth permitted' then raise; end if; end;
end $$;
select 'PASS: create, recruit, validation, upgrades, transport, PvE, cooldown, PvP, Elo, permanence, offline production, RLS, authenticated RPC, auth guard' as result;
rollback;

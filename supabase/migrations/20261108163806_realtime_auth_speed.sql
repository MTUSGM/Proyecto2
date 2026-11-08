-- Apply once after orbital_upgrade.sql. No resets or deletion of game records.
-- Settle old production at the old rate before activating the new rate.
update public.empire set
 minerals=least(20000,minerals+least(86400,greatest(0,extract(epoch from now()-collected_at)))/3600*120*mine),
 energy=least(20000,energy+least(86400,greatest(0,extract(epoch from now()-collected_at)))/3600*90*reactor),
 supplies=least(20000,supplies+least(86400,greatest(0,extract(epoch from now()-collected_at)))/3600*75*farm),
 collected_at=now(),
 shield_until=case when shield_until>now() then now()+(shield_until-now())/2 else shield_until end,
 attack_at=case when attack_at>now()-interval '60 seconds' then now()-interval '30 seconds'+(attack_at+interval '60 seconds'-now())/2 else attack_at end;
create or replace function private.game_timing() returns jsonb language sql immutable set search_path='' as $$
 select '{"attack_cooldown_seconds":30,"shield_seconds":300,"production_multiplier":2,"offline_cap_seconds":43200}'::jsonb;
$$;
revoke all on function private.game_timing() from public,anon,authenticated;
alter table public.empire alter column shield_until set default now()+interval '5 minutes';
alter table public.commanders add column state_version bigint not null default 0;
alter table public.battles add column request_id uuid;
create unique index battles_request_unique on public.battles(attacker,request_id) where request_id is not null;
create table public.attack_notifications (
 id uuid primary key references public.battles(id) on delete cascade,
 recipient uuid not null references public.commanders(id) on delete cascade,
 attacker uuid not null references public.commanders(id) on delete cascade,
 attacker_name text not null, planet text not null, attacker_won boolean not null,
 created_at timestamptz not null, read_at timestamptz
);
create index notifications_recipient_unread on public.attack_notifications(recipient,created_at desc) where read_at is null;
create index notifications_attacker on public.attack_notifications(attacker);
alter table public.attack_notifications enable row level security;
revoke all on public.attack_notifications from anon,authenticated;
grant select on public.attack_notifications to authenticated;
grant update(read_at) on public.attack_notifications to authenticated;
create policy notifications_read on public.attack_notifications for select to authenticated using(recipient=(select auth.uid()));
create policy notifications_mark_read on public.attack_notifications for update to authenticated using(recipient=(select auth.uid())) with check(recipient=(select auth.uid()));
create function private.notify_attack() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if new.defender is not null then
  insert into public.attack_notifications(id,recipient,attacker,attacker_name,planet,attacker_won,created_at)
  values(new.id,new.defender,new.attacker,new.report->>'attacker_name',new.report->>'target',(new.report->>'won')::boolean,new.created_at);
 end if;
 return new;
end; $$;
revoke all on function private.notify_attack() from public,anon,authenticated;
create trigger battle_notification after insert on public.battles for each row execute function private.notify_attack();
-- Public commander revisions signal changes to already-public tactical intelligence.
-- Resources and other private empire data remain protected by the original RLS.
create function private.signal_empire_change() returns trigger language plpgsql security definer set search_path='' as $$
begin
 if row(new.ground,new.embarked,new.fleet,new.transports,new.warships,new.tech,new.defense,new.orbital,new.shield_until)
 is distinct from row(old.ground,old.embarked,old.fleet,old.transports,old.warships,old.tech,old.defense,old.orbital,old.shield_until) then
  update public.commanders set state_version=state_version+1 where id=new.id;
 end if;
 return new;
end; $$;
revoke all on function private.signal_empire_change() from public,anon,authenticated;
create trigger empire_revision after update on public.empire for each row execute function private.signal_empire_change();
alter publication supabase_realtime add table public.commanders,public.empire,public.battles,public.attack_notifications;

create or replace function private.game(action text, payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
 uid uuid := auth.uid(); me public.commanders; e public.empire; enemy public.commanders; d public.empire;
 n integer; target uuid; kind text; cm numeric:=0; ce numeric:=0; cs numeric:=0; lvl integer;
 elapsed numeric; atk numeric; def numeric; roll numeric; won boolean; lost integer; dlost integer:=0;
 delta integer:=0; reward integer:=0; sent integer; label text; result jsonb; report jsonb; npc integer;
 unit_key text; spec jsonb; desired jsonb; sent_units jsonb; defender_units jsonb;
 losses jsonb:='{}'; defender_losses jsonb:='{}'; capacity integer:=0; count_units integer; casualties integer;
 chosen_fleet jsonb; ship_spec jsonb; npc_data jsonb; defender_faction text; defender_tech int; bastion int;
 orbital_atk numeric; orbital_def numeric; orbital_roll numeric; orbital_won boolean; orbital_rate numeric;
 landed jsonb:='{}'; orbital_losses jsonb:='{}'; land_loss integer; orbital_loss integer; support numeric; repairs int;
begin
 if uid is null then raise exception 'Inicia sesión para jugar.'; end if;
 if action not in ('state','create','recruit','ship','upgrade','embark','attack') or action is null then raise exception 'Acción inválida.'; end if;
 perform pg_advisory_xact_lock(87214001);
 select * into me from public.commanders where id=uid;
 if action='create' then
  if me.id is not null then raise exception 'Ya tienes un planeta.'; end if;
  insert into public.commanders(id,name,planet,faction) values(uid,trim(payload->>'name'),trim(payload->>'planet'),payload->>'faction');
  insert into public.empire(id) values(uid);
  select * into me from public.commanders where id=uid;
 end if;
 if me.id is null then return jsonb_build_object('commander',null); end if;
 select * into e from public.empire where id=uid for update;
 elapsed := least((private.game_timing()->>'offline_cap_seconds')::numeric,greatest(0,extract(epoch from now()-e.collected_at)))/3600*(private.game_timing()->>'production_multiplier')::numeric;
 e.minerals := least(20000,e.minerals+elapsed*120*e.mine);
 e.energy := least(20000,e.energy+elapsed*90*e.reactor);
 e.supplies := least(20000,e.supplies+elapsed*75*e.farm);
 if action='recruit' then
  n := (payload->>'quantity')::integer;
  if n is null or n<1 or n>1000 then raise exception 'Cantidad entre 1 y 1000.'; end if;
  unit_key:=coalesce(payload->>'unit','ranged');
  spec:=private.unit_catalog()->me.faction->unit_key;
  if spec is null then raise exception 'Tipo de unidad inválido.'; end if;
  cm:=n*(spec->>'minerals')::numeric; ce:=n*(spec->>'energy')::numeric; cs:=n*(spec->>'supplies')::numeric;
  if me.faction='orkos' then cm:=cm*0.8; ce:=ce*0.8; cs:=cs*0.8; end if;
  e.ground:=jsonb_set(e.ground,array[unit_key],to_jsonb((e.ground->>unit_key)::integer+n));
 elsif action='embark' then
  desired:=payload->'units';
  chosen_fleet:=payload->'fleet';
  if not private.valid_fleet(chosen_fleet) then raise exception 'Elige la composición de naves y guarda la flota (actualiza la página).'; end if;
  if (chosen_fleet->>'transport')::int>e.transports or (chosen_fleet->>'combat')::int>e.warships then raise exception 'No tienes suficientes naves de ese tipo.'; end if;
  if not private.valid_units(desired) then raise exception 'Composición inválida: utiliza cantidades enteras no negativas para cada tipo.'; end if;
  foreach unit_key in array array['ranged','melee','tank'] loop
   n:=(desired->>unit_key)::integer;
   count_units:=(e.ground->>unit_key)::integer+(e.embarked->>unit_key)::integer;
   if n>count_units then raise exception 'No tienes suficientes unidades de tipo %.',unit_key; end if;
   capacity:=capacity+n*(private.unit_catalog()->me.faction->unit_key->>'space')::integer;
   e.ground:=jsonb_set(e.ground,array[unit_key],to_jsonb(count_units-n));
  end loop;
  if capacity>(chosen_fleet->>'transport')::int*30+(chosen_fleet->>'combat')::int*10 then raise exception 'Capacidad superada: infantería 1 plaza, tanques 5 plazas.'; end if;
  e.embarked:=desired; e.fleet:=chosen_fleet;
 elsif action='ship' then
  kind:=coalesce(payload->>'type','transport');
  ship_spec:=private.ship_catalog()->kind;
  if ship_spec is null then raise exception 'Tipo de nave inválido.'; end if;
  cm:=(ship_spec->>'minerals')::numeric; ce:=(ship_spec->>'energy')::numeric; cs:=(ship_spec->>'supplies')::numeric;
  if kind='transport' then e.transports:=e.transports+1; else e.warships:=e.warships+1; end if;
  e.ships:=e.transports+e.warships;
 elsif action='upgrade' then
  kind:=payload->>'building';
  lvl:=case kind when 'mine' then e.mine when 'reactor' then e.reactor when 'farm' then e.farm when 'defense' then e.defense when 'tech' then e.tech when 'orbital' then e.orbital else null end;
  if lvl is null or lvl>=10 then raise exception 'Mejora inválida o nivel máximo alcanzado.'; end if;
  cm:=150*greatest(1,lvl); ce:=100*greatest(1,lvl);
  if kind='mine' then e.mine:=e.mine+1;
  elsif kind='reactor' then e.reactor:=e.reactor+1;
  elsif kind='farm' then e.farm:=e.farm+1;
  elsif kind='defense' then e.defense:=e.defense+1;
  elsif kind='orbital' then e.orbital:=e.orbital+1;
  else e.tech:=e.tech+1; end if;
 elsif action='attack' then
  if payload ? 'request_id' and exists(select 1 from public.battles where attacker=uid and request_id=(payload->>'request_id')::uuid) then raise exception 'Esta orden de ataque ya fue procesada. Revisa los informes.'; end if;
  if e.attack_at is not null and e.attack_at > now()-make_interval(secs => (private.game_timing()->>'attack_cooldown_seconds')::int) then raise exception 'La flota se está reagrupando. Espera 30 segundos entre ataques.'; end if;
  if payload ? 'troops' then raise exception 'Actualiza la página y embarca una composición antes de atacar.'; end if;
  sent_units:=e.embarked;
  sent:=0;
  foreach unit_key in array array['ranged','melee','tank'] loop
   n:=(sent_units->>unit_key)::integer; sent:=sent+n;
   spec:=private.unit_catalog()->me.faction->unit_key;
   capacity:=capacity+n*(spec->>'space')::integer;
   cs:=cs+n*(spec->>'upkeep')::numeric;
  end loop;
  if sent<1 then raise exception 'Embarca unidades antes de atacar.'; end if;
  ce:=(e.fleet->>'transport')::int*25+(e.fleet->>'combat')::int*70;
  cs:=cs+(e.fleet->>'transport')::int*5+(e.fleet->>'combat')::int*15;
  orbital_atk:=(e.fleet->>'transport')::int*12+(e.fleet->>'combat')::int*120;
  if orbital_atk<=0 then raise exception 'Asigna naves a la expedición.'; end if;
  if payload->>'target' is not null then
   target:=(payload->>'target')::uuid;
   if target=uid then raise exception 'No puedes atacar tu propio planeta.'; end if;
   select * into enemy from public.commanders where id=target;
   select * into d from public.empire where id=target for update;
   if enemy.id is null then raise exception 'Objetivo inexistente.'; end if;
   if d.shield_until>now() then raise exception 'Este planeta tiene un escudo temporal. Elige otro objetivo.'; end if;
   defender_units:=d.ground;
   defender_faction:=enemy.faction; defender_tech:=d.tech; bastion:=d.defense;
   orbital_def:=d.orbital*80+(d.transports-(d.fleet->>'transport')::int)*12+(d.warships-(d.fleet->>'combat')::int)*100;
   label:=enemy.planet;
  else
   npc:=(payload->>'npc')::integer;
   if npc is null or npc not between 1 and 3 then raise exception 'Selecciona un nido tiránido válido.'; end if;
   npc_data:=private.npc_catalog()->(npc-1);
   defender_units:=npc_data->'ground'; defender_faction:='tiranidos'; defender_tech:=(npc_data->>'tech')::int; bastion:=(npc_data->>'defense')::int;
   orbital_def:=(npc_data->>'orbital_power')::numeric; label:=npc_data->>'name';
  end if;
  repairs:=ceil(least(2,orbital_def/greatest(1,orbital_atk))*((e.fleet->>'transport')::int+(e.fleet->>'combat')::int)*10)::int;
  ce:=ce+repairs;
  if e.energy<ce or e.supplies<cs then raise exception 'Recursos insuficientes para combustible, suministros y reparación orbital.'; end if;
  orbital_roll:=0.85+random()*0.3; orbital_won:=orbital_atk*orbital_roll>=orbital_def;
  orbital_rate:=case when orbital_won then least(0.20,0.15*orbital_def/greatest(1,orbital_atk)) else 0.25 end;
  foreach unit_key in array array['ranged','melee','tank'] loop
   n:=(sent_units->>unit_key)::int;
   orbital_loss:=least(n,ceil(n*orbital_rate*(1-(private.unit_catalog()->me.faction->unit_key->>'armor')::numeric/100))::int);
   orbital_losses:=jsonb_set(orbital_losses,array[unit_key],to_jsonb(orbital_loss));
   landed:=jsonb_set(landed,array[unit_key],to_jsonb(n-orbital_loss));
  end loop;
  atk:=private.tactical_power(landed,me.faction,e.tech,false,defender_units)*(case when me.faction='orkos' then 1.1 else 1 end);
  support:=least(atk*0.25,(e.fleet->>'transport')::int+(e.fleet->>'combat')::int*6);
  atk:=atk+support;
  def:=(private.tactical_power(defender_units,defender_faction,defender_tech,true,landed)+bastion*100)*(case when defender_faction='imperio' then 1.15 else 1 end);
  roll:=0.85+random()*0.3;
  won:=orbital_won and atk>0 and atk*roll>=def;
  lost:=0;
  foreach unit_key in array array['ranged','melee','tank'] loop
   n:=(sent_units->>unit_key)::integer;
   spec:=private.unit_catalog()->me.faction->unit_key;
   orbital_loss:=(orbital_losses->>unit_key)::int;
   land_loss:=case when orbital_won then least(n-orbital_loss,ceil((n-orbital_loss)*(case when won then 0.12 else 0.35 end)*(1-(spec->>'armor')::numeric/100))::int) else 0 end;
   casualties:=orbital_loss+land_loss;
   losses:=jsonb_set(losses,array[unit_key],to_jsonb(casualties)); lost:=lost+casualties;
   e.embarked:=jsonb_set(e.embarked,array[unit_key],to_jsonb(n-casualties));
  end loop;
  if orbital_won then
   foreach unit_key in array array['ranged','melee','tank'] loop
    n:=(defender_units->>unit_key)::integer;
    spec:=private.unit_catalog()->defender_faction->unit_key;
    casualties:=least(n,ceil(n*(case when won then 0.30 else 0.10 end)*(1-(spec->>'armor')::numeric/100))::integer);
    defender_losses:=jsonb_set(defender_losses,array[unit_key],to_jsonb(casualties)); dlost:=dlost+casualties;
    if target is not null then d.ground:=jsonb_set(d.ground,array[unit_key],to_jsonb(n-casualties)); end if;
   end loop;
  end if;
  if target is not null then
   delta:=round(32*((case when won then 1 else 0 end)-1/(1+power(10::numeric,(enemy.elo-me.elo)/400.0))))::integer;
   -- Transfer conserves rating even at the zero floor.
   delta:=greatest(-me.elo,least(enemy.elo,delta));
   reward:=case when won then least(300,floor(d.minerals*0.1)::integer) else 0 end;
   update public.empire set ground=d.ground,troops=troops-dlost,minerals=minerals-reward,shield_until=now()+make_interval(secs => (private.game_timing()->>'shield_seconds')::int) where id=target;
   update public.commanders set elo=elo-delta,battles=battles+1,wins=wins+case when won then 0 else 1 end where id=target;
  else reward:=case when won then npc*180 else 0 end; end if;
  e.minerals:=least(20000,e.minerals+reward);
  e.loot:=e.loot+case when won then (case when me.faction='herejes' then 15 else 10 end)*coalesce(npc,1) else 0 end;
  e.attack_at:=now(); e.shield_until:=now();
  update public.commanders set elo=elo+delta,battles=battles+1,wins=wins+case when won then 1 else 0 end where id=uid;
  report:=jsonb_build_object('attacker_name',me.name,'defender_name',coalesce(enemy.name,'Tiránidos'),'target',label,'won',won,'sent',sent,'lost',lost,'defender_lost',dlost,'attack_power',round(atk),'defense_power',round(def),'roll',round(roll,3),'reward',reward,'elo_delta',delta,'pvp',target is not null,'sent_units',sent_units,'losses',losses,'defender_units',defender_units,'defender_losses',defender_losses,'attacker_faction',me.faction,'defender_faction',defender_faction,'orbital_won',orbital_won,'orbital_attack',orbital_atk,'orbital_defense',orbital_def,'orbital_roll',round(orbital_roll,3),'orbital_losses',orbital_losses,'landed',landed,'fleet',e.fleet,'support',round(support,2),'energy_cost',ce,'supplies_cost',cs,'repair_cost',repairs,'ground_fought',orbital_won);
  insert into public.battles(attacker,defender,report,request_id) values(uid,target,report,(payload->>'request_id')::uuid);
 end if;
 if e.minerals<cm or e.energy<ce or e.supplies<cs then raise exception 'Recursos insuficientes.'; end if;
 e.troops:=(e.ground->>'ranged')::integer+(e.ground->>'melee')::integer+(e.ground->>'tank')::integer+(e.embarked->>'ranged')::integer+(e.embarked->>'melee')::integer+(e.embarked->>'tank')::integer;
 if action <> 'state' then
 update public.empire set transports=e.transports,warships=e.warships,orbital=e.orbital,fleet=e.fleet,ground=e.ground,embarked=e.embarked,minerals=e.minerals-cm,energy=e.energy-ce,supplies=e.supplies-cs,loot=e.loot,troops=e.troops,ships=e.ships,mine=e.mine,reactor=e.reactor,farm=e.farm,defense=e.defense,tech=e.tech,collected_at=now(),attack_at=e.attack_at,shield_until=e.shield_until where id=uid;
 end if;
 select jsonb_build_object(
  'timing',private.game_timing(),
  'notifications',coalesce((select jsonb_agg(to_jsonb(notice) order by notice.created_at desc) from public.attack_notifications notice where notice.recipient=uid and notice.read_at is null),'[]'::jsonb),
  'ship_catalog',private.ship_catalog(),'npc_catalog',private.npc_catalog(),'all_units',private.unit_catalog(),
  'unit_catalog',private.unit_catalog()->me.faction,
  'commander',(select to_jsonb(c) from public.commanders c where id=uid),
  'empire',case when action='state' then to_jsonb(e) else (select to_jsonb(x) from public.empire x where id=uid) end,
  'ranking',coalesce((select jsonb_agg(to_jsonb(r)) from (select c.*,x.shield_until,x.ground,x.tech,x.defense,(x.orbital*80+(x.transports-(x.fleet->>'transport')::int)*12+(x.warships-(x.fleet->>'combat')::int)*100) as orbital_power from public.commanders c join public.empire x using(id) order by c.elo desc,c.created_at limit 100) r),'[]'::jsonb),
  'reports',coalesce((select jsonb_agg(to_jsonb(b)) from (select * from public.battles where attacker=uid or defender=uid order by created_at desc limit 30) b),'[]'::jsonb),
  'last_battle',report,'server_time',now()) into result;
 return result;
end; $$;

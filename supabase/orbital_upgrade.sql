-- Apply after units_upgrade.sql. Old ships become armed transports.
alter table public.empire add column transports integer not null default 2 check(transports>=0), add column warships integer not null default 0 check(warships>=0), add column orbital integer not null default 0 check(orbital between 0 and 10), add column fleet jsonb not null default '{"transport":0,"combat":0}';
update public.empire set transports=ships,fleet=jsonb_build_object('transport',ceil(((embarked->>'ranged')::numeric+(embarked->>'melee')::numeric+5*(embarked->>'tank')::numeric)/30)::int,'combat',0);
create or replace function private.valid_fleet(f jsonb) returns boolean language sql immutable set search_path='' as $$
 select coalesce(jsonb_typeof(f)='object' and f ?& array['transport','combat'] and (f-array['transport','combat'])='{}'::jsonb and (f->>'transport') ~ '^(0|[1-9][0-9]{0,6})$' and (f->>'combat') ~ '^(0|[1-9][0-9]{0,6})$',false);
$$;
alter table public.empire add constraint valid_fleet check(private.valid_fleet(fleet)), add constraint owned_fleet check((fleet->>'transport')::int<=transports and (fleet->>'combat')::int<=warships);
create or replace function private.unit_catalog() returns jsonb language sql immutable set search_path='' as $$ select '{"imperio": {"ranged": {"name": "Fusilero imperial", "attack": 10, "defense": 14, "armor": 10, "minerals": 12, "energy": 2, "supplies": 8, "space": 1, "upkeep": 2, "description": "Infantería disciplinada: destaca defendiendo posiciones."}, "melee": {"name": "Guardia de asalto", "attack": 15, "defense": 9, "armor": 15, "minerals": 14, "energy": 0, "supplies": 10, "space": 1, "upkeep": 2, "description": "Especialista ofensivo con protección ligera."}, "tank": {"name": "Tanque Bastión", "attack": 65, "defense": 85, "armor": 55, "minerals": 150, "energy": 65, "supplies": 40, "space": 5, "upkeep": 10, "description": "Blindaje pesado y gran defensa; exige mucho transporte."}}, "orkos": {"ranged": {"name": "Tirador orko", "attack": 11, "defense": 9, "armor": 5, "minerals": 10, "energy": 0, "supplies": 8, "space": 1, "upkeep": 2, "description": "Fuego abundante y económico, con poca protección."}, "melee": {"name": "Guerrero de hacha", "attack": 18, "defense": 8, "armor": 10, "minerals": 12, "energy": 0, "supplies": 9, "space": 1, "upkeep": 2, "description": "Asalto brutal y barato; vulnerable al defender."}, "tank": {"name": "Carro de guerra", "attack": 80, "defense": 55, "armor": 40, "minerals": 130, "energy": 55, "supplies": 45, "space": 5, "upkeep": 12, "description": "Gran potencia ofensiva; menos blindado y consume más suministros."}}, "herejes": {"ranged": {"name": "Acólito de fuego", "attack": 13, "defense": 11, "armor": 8, "minerals": 14, "energy": 4, "supplies": 8, "space": 1, "upkeep": 2, "description": "Potencia de fuego elevada a cambio de energía."}, "melee": {"name": "Berserker del vacío", "attack": 20, "defense": 7, "armor": 5, "minerals": 17, "energy": 3, "supplies": 10, "space": 1, "upkeep": 3, "description": "Ataque extremo; defensa y protección reducidas."}, "tank": {"name": "Destructor profano", "attack": 90, "defense": 60, "armor": 45, "minerals": 170, "energy": 80, "supplies": 45, "space": 5, "upkeep": 12, "description": "El mayor ataque base; costoso de fabricar y desplegar."}}, "tiranidos": {"ranged": {"name": "Termagante", "attack": 9, "defense": 11, "armor": 5, "space": 1}, "melee": {"name": "Hormagante", "attack": 16, "defense": 9, "armor": 8, "space": 1}, "tank": {"name": "Carnifex", "attack": 80, "defense": 70, "armor": 50, "space": 5}}}'::jsonb; $$;
create or replace function private.ship_catalog() returns jsonb language sql immutable set search_path='' as $$ select '{"transport": {"name": "Transporte armado", "capacity": 30, "attack": 12, "defense": 12, "bombard": 1, "minerals": 300, "energy": 200, "supplies": 40, "fuel": 25, "upkeep": 5}, "combat": {"name": "Fragata de combate", "capacity": 10, "attack": 120, "defense": 100, "bombard": 6, "minerals": 600, "energy": 400, "supplies": 100, "fuel": 70, "upkeep": 15}}'::jsonb; $$;
create or replace function private.npc_catalog() returns jsonb language sql immutable set search_path='' as $$ select '[{"id": 1, "name": "Nido Caronte", "label": "Enjambre de exploración", "x": 26, "y": 40, "ground": {"ranged": 20, "melee": 10, "tank": 0}, "orbital_power": 20, "defense": 0, "tech": 1, "faction": "tiranidos", "reward": 180}, {"id": 2, "name": "Colmena Vesper", "label": "Enjambre de asalto", "x": 66, "y": 28, "ground": {"ranged": 15, "melee": 45, "tank": 2}, "orbital_power": 160, "defense": 1, "tech": 1, "faction": "tiranidos", "reward": 360}, {"id": 3, "name": "Leviatán IX", "label": "Fortaleza bioacorazada", "x": 75, "y": 72, "ground": {"ranged": 30, "melee": 15, "tank": 10}, "orbital_power": 360, "defense": 3, "tech": 2, "faction": "tiranidos", "reward": 540}]'::jsonb; $$;

-- Weighted by transport footprint, so one heavy creature counts as five infantry.
create or replace function private.tactical_power(units jsonb,faction text,tech integer,defending boolean,opponent jsonb) returns numeric language plpgsql immutable set search_path='' as $$
declare k text; good text; bad text; total numeric; mult numeric; score numeric:=0;
begin
 total:=(opponent->>'ranged')::numeric+(opponent->>'melee')::numeric+5*(opponent->>'tank')::numeric;
 foreach k in array array['ranged','melee','tank'] loop
  good:=case k when 'ranged' then 'melee' when 'melee' then 'tank' else 'ranged' end;
  bad:=case k when 'ranged' then 'tank' when 'melee' then 'ranged' else 'melee' end;
  mult:=case when total=0 then 1 else 1+0.5*(opponent->>good)::numeric*(case when good='tank' then 5 else 1 end)/total-0.25*(opponent->>bad)::numeric*(case when bad='tank' then 5 else 1 end)/total end;
  score:=score+(units->>k)::numeric*(private.unit_catalog()->faction->k->>(case when defending then 'defense' else 'attack' end))::numeric*mult;
 end loop;
 return score*(1+(tech-1)*0.15);
end; $$;
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
 elapsed := least(86400,greatest(0,extract(epoch from now()-e.collected_at)))/3600;
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
  if e.attack_at is not null and e.attack_at > now()-interval '60 seconds' then raise exception 'La flota se está reagrupando. Espera 60 segundos entre ataques.'; end if;
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
   update public.empire set ground=d.ground,troops=troops-dlost,minerals=minerals-reward,shield_until=now()+interval '10 minutes' where id=target;
   update public.commanders set elo=elo-delta,battles=battles+1,wins=wins+case when won then 0 else 1 end where id=target;
  else reward:=case when won then npc*180 else 0 end; end if;
  e.minerals:=least(20000,e.minerals+reward);
  e.loot:=e.loot+case when won then (case when me.faction='herejes' then 15 else 10 end)*coalesce(npc,1) else 0 end;
  e.attack_at:=now(); e.shield_until:=now();
  update public.commanders set elo=elo+delta,battles=battles+1,wins=wins+case when won then 1 else 0 end where id=uid;
  report:=jsonb_build_object('attacker_name',me.name,'defender_name',coalesce(enemy.name,'Tiránidos'),'target',label,'won',won,'sent',sent,'lost',lost,'defender_lost',dlost,'attack_power',round(atk),'defense_power',round(def),'roll',round(roll,3),'reward',reward,'elo_delta',delta,'pvp',target is not null,'sent_units',sent_units,'losses',losses,'defender_units',defender_units,'defender_losses',defender_losses,'attacker_faction',me.faction,'defender_faction',defender_faction,'orbital_won',orbital_won,'orbital_attack',orbital_atk,'orbital_defense',orbital_def,'orbital_roll',round(orbital_roll,3),'orbital_losses',orbital_losses,'landed',landed,'fleet',e.fleet,'support',round(support,2),'energy_cost',ce,'supplies_cost',cs,'repair_cost',repairs,'ground_fought',orbital_won);
  insert into public.battles(attacker,defender,report) values(uid,target,report);
 end if;
 if e.minerals<cm or e.energy<ce or e.supplies<cs then raise exception 'Recursos insuficientes.'; end if;
 e.troops:=(e.ground->>'ranged')::integer+(e.ground->>'melee')::integer+(e.ground->>'tank')::integer+(e.embarked->>'ranged')::integer+(e.embarked->>'melee')::integer+(e.embarked->>'tank')::integer;
 update public.empire set transports=e.transports,warships=e.warships,orbital=e.orbital,fleet=e.fleet,ground=e.ground,embarked=e.embarked,minerals=e.minerals-cm,energy=e.energy-ce,supplies=e.supplies-cs,loot=e.loot,troops=e.troops,ships=e.ships,mine=e.mine,reactor=e.reactor,farm=e.farm,defense=e.defense,tech=e.tech,collected_at=now(),attack_at=e.attack_at,shield_until=e.shield_until where id=uid;
 select jsonb_build_object(
  'ship_catalog',private.ship_catalog(),'npc_catalog',private.npc_catalog(),'all_units',private.unit_catalog(),
  'unit_catalog',private.unit_catalog()->me.faction,
  'commander',(select to_jsonb(c) from public.commanders c where id=uid),
  'empire',(select to_jsonb(x) from public.empire x where id=uid),
  'ranking',coalesce((select jsonb_agg(to_jsonb(r)) from (select c.*,x.shield_until,x.ground,x.tech,x.defense,(x.orbital*80+(x.transports-(x.fleet->>'transport')::int)*12+(x.warships-(x.fleet->>'combat')::int)*100) as orbital_power from public.commanders c join public.empire x using(id) order by c.elo desc,c.created_at limit 100) r),'[]'::jsonb),
  'reports',coalesce((select jsonb_agg(to_jsonb(b)) from (select * from public.battles where attacker=uid or defender=uid order by created_at desc limit 30) b),'[]'::jsonb),
  'last_battle',report,'server_time',now()) into result;
 return result;
end; $$;


revoke all on function private.ship_catalog(),private.npc_catalog(),private.tactical_power(jsonb,text,integer,boolean,jsonb),private.valid_fleet(jsonb) from public,anon,authenticated;
grant execute on function private.valid_fleet(jsonb) to authenticated;

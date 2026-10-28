-- Upgrade after schema.sql; preserves existing armies as ranged infantry.
alter table public.empire add column ground jsonb not null default '{"ranged":40,"melee":0,"tank":0}';
alter table public.empire add column embarked jsonb not null default '{"ranged":0,"melee":0,"tank":0}';
update public.empire set ground=jsonb_build_object('ranged',troops,'melee',0,'tank',0);
create or replace function private.valid_units(units jsonb) returns boolean
language sql immutable set search_path='' as $$
 select coalesce(jsonb_typeof(units)='object' and units ?& array['ranged','melee','tank']
 and (units - array['ranged','melee','tank'])='{}'::jsonb
 and (units->>'ranged') ~ '^(0|[1-9][0-9]{0,6})$'
 and (units->>'melee') ~ '^(0|[1-9][0-9]{0,6})$'
 and (units->>'tank') ~ '^(0|[1-9][0-9]{0,6})$',false);
$$;
alter table public.empire add constraint valid_ground check(private.valid_units(ground)), add constraint valid_embarked check(private.valid_units(embarked));
create or replace function private.unit_catalog() returns jsonb language sql immutable set search_path='' as $$ select '{"imperio": {"ranged": {"name": "Fusilero imperial", "attack": 10, "defense": 14, "armor": 10, "minerals": 12, "energy": 2, "supplies": 8, "space": 1, "upkeep": 2, "description": "Infantería disciplinada: destaca defendiendo posiciones."}, "melee": {"name": "Guardia de asalto", "attack": 15, "defense": 9, "armor": 15, "minerals": 14, "energy": 0, "supplies": 10, "space": 1, "upkeep": 2, "description": "Especialista ofensivo con protección ligera."}, "tank": {"name": "Tanque Bastión", "attack": 65, "defense": 85, "armor": 55, "minerals": 150, "energy": 65, "supplies": 40, "space": 5, "upkeep": 10, "description": "Blindaje pesado y gran defensa; exige mucho transporte."}}, "orkos": {"ranged": {"name": "Tirador orko", "attack": 11, "defense": 9, "armor": 5, "minerals": 10, "energy": 0, "supplies": 8, "space": 1, "upkeep": 2, "description": "Fuego abundante y económico, con poca protección."}, "melee": {"name": "Guerrero de hacha", "attack": 18, "defense": 8, "armor": 10, "minerals": 12, "energy": 0, "supplies": 9, "space": 1, "upkeep": 2, "description": "Asalto brutal y barato; vulnerable al defender."}, "tank": {"name": "Carro de guerra", "attack": 80, "defense": 55, "armor": 40, "minerals": 130, "energy": 55, "supplies": 45, "space": 5, "upkeep": 12, "description": "Gran potencia ofensiva; menos blindado y consume más suministros."}}, "herejes": {"ranged": {"name": "Acólito de fuego", "attack": 13, "defense": 11, "armor": 8, "minerals": 14, "energy": 4, "supplies": 8, "space": 1, "upkeep": 2, "description": "Potencia de fuego elevada a cambio de energía."}, "melee": {"name": "Berserker del vacío", "attack": 20, "defense": 7, "armor": 5, "minerals": 17, "energy": 3, "supplies": 10, "space": 1, "upkeep": 3, "description": "Ataque extremo; defensa y protección reducidas."}, "tank": {"name": "Destructor profano", "attack": 90, "defense": 60, "armor": 45, "minerals": 170, "energy": 80, "supplies": 45, "space": 5, "upkeep": 12, "description": "El mayor ataque base; costoso de fabricar y desplegar."}}}'::jsonb; $$;
create or replace function private.army_power(units jsonb, faction text, tech integer, defending boolean)
returns numeric language sql immutable set search_path='' as $$
 select coalesce(sum((u.value::text)::integer * ((private.unit_catalog()->faction->u.key)->>(case when defending then 'defense' else 'attack' end))::numeric),0)*(1+(tech-1)*0.15)
 from jsonb_each(units) u;
$$;
create or replace function private.game(action text, payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
 uid uuid := auth.uid(); me public.commanders; e public.empire; enemy public.commanders; d public.empire;
 n integer; target uuid; kind text; cm numeric:=0; ce numeric:=0; cs numeric:=0; lvl integer;
 elapsed numeric; atk numeric; def numeric; roll numeric; won boolean; lost integer; dlost integer:=0;
 delta integer:=0; reward integer:=0; sent integer; label text; result jsonb; report jsonb; npc integer;
 unit_key text; spec jsonb; desired jsonb; sent_units jsonb; defender_units jsonb;
 losses jsonb:='{}'; defender_losses jsonb:='{}'; capacity integer:=0; count_units integer; casualties integer;
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
  if not private.valid_units(desired) then raise exception 'Composición inválida: utiliza cantidades enteras no negativas para cada tipo.'; end if;
  foreach unit_key in array array['ranged','melee','tank'] loop
   n:=(desired->>unit_key)::integer;
   count_units:=(e.ground->>unit_key)::integer+(e.embarked->>unit_key)::integer;
   if n>count_units then raise exception 'No tienes suficientes unidades de tipo %.',unit_key; end if;
   capacity:=capacity+n*(private.unit_catalog()->me.faction->unit_key->>'space')::integer;
   e.ground:=jsonb_set(e.ground,array[unit_key],to_jsonb(count_units-n));
  end loop;
  if capacity>e.ships*30 then raise exception 'Capacidad superada: infantería 1 plaza, tanques 5 plazas.'; end if;
  e.embarked:=desired;
 elsif action='ship' then
  cm:=300; ce:=200; e.ships:=e.ships+1;
 elsif action='upgrade' then
  kind:=payload->>'building';
  lvl:=case kind when 'mine' then e.mine when 'reactor' then e.reactor when 'farm' then e.farm when 'defense' then e.defense when 'tech' then e.tech else null end;
  if lvl is null or lvl>=10 then raise exception 'Mejora inválida o nivel máximo alcanzado.'; end if;
  cm:=150*lvl; ce:=100*lvl;
  if kind='mine' then e.mine:=e.mine+1;
  elsif kind='reactor' then e.reactor:=e.reactor+1;
  elsif kind='farm' then e.farm:=e.farm+1;
  elsif kind='defense' then e.defense:=e.defense+1;
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
  ce:=25*ceil(capacity/30.0);
  if payload->>'target' is not null then
   target:=(payload->>'target')::uuid;
   if target=uid then raise exception 'No puedes atacar tu propio planeta.'; end if;
   select * into enemy from public.commanders where id=target;
   select * into d from public.empire where id=target for update;
   if enemy.id is null then raise exception 'Objetivo inexistente.'; end if;
   if d.shield_until>now() then raise exception 'Este planeta tiene un escudo temporal. Elige otro objetivo.'; end if;
   defender_units:=d.ground;
   def:=(private.army_power(d.ground,enemy.faction,d.tech,true)+d.defense*100)*(case when enemy.faction='imperio' then 1.15 else 1 end);
   label:=enemy.planet;
  else
   npc:=(payload->>'npc')::integer;
   if npc is null or npc not between 1 and 3 then raise exception 'Selecciona un nido tiránido válido.'; end if;
   def:=case npc when 1 then 250 when 2 then 750 else 1800 end;
   label:=case npc when 1 then 'Nido Caronte' when 2 then 'Colmena Vesper' else 'Leviatán IX' end;
  end if;
  atk:=private.army_power(sent_units,me.faction,e.tech,false)*(case when me.faction='orkos' then 1.1 else 1 end)+ceil(capacity/30.0)*20;
  roll:=0.85+random()*0.3;
  won:=atk*roll>=def;
  lost:=0;
  foreach unit_key in array array['ranged','melee','tank'] loop
   n:=(sent_units->>unit_key)::integer;
   spec:=private.unit_catalog()->me.faction->unit_key;
   casualties:=least(n,ceil(n*(case when won then 0.12 else 0.35 end)*(1-(spec->>'armor')::numeric/100))::integer);
   losses:=jsonb_set(losses,array[unit_key],to_jsonb(casualties)); lost:=lost+casualties;
   e.embarked:=jsonb_set(e.embarked,array[unit_key],to_jsonb(n-casualties));
  end loop;
  if target is not null then
   foreach unit_key in array array['ranged','melee','tank'] loop
    n:=(d.ground->>unit_key)::integer;
    spec:=private.unit_catalog()->enemy.faction->unit_key;
    casualties:=least(n,ceil(n*(case when won then 0.30 else 0.10 end)*(1-(spec->>'armor')::numeric/100))::integer);
    defender_losses:=jsonb_set(defender_losses,array[unit_key],to_jsonb(casualties)); dlost:=dlost+casualties;
    d.ground:=jsonb_set(d.ground,array[unit_key],to_jsonb(n-casualties));
   end loop;
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
  report:=jsonb_build_object('attacker_name',me.name,'defender_name',coalesce(enemy.name,'Tiránidos'),'target',label,'won',won,'sent',sent,'lost',lost,'defender_lost',dlost,'attack_power',round(atk),'defense_power',round(def),'roll',round(roll,3),'reward',reward,'elo_delta',delta,'pvp',target is not null,'sent_units',sent_units,'losses',losses,'defender_units',defender_units,'defender_losses',defender_losses,'attacker_faction',me.faction,'defender_faction',enemy.faction);
  insert into public.battles(attacker,defender,report) values(uid,target,report);
 end if;
 if e.minerals<cm or e.energy<ce or e.supplies<cs then raise exception 'Recursos insuficientes.'; end if;
 e.troops:=(e.ground->>'ranged')::integer+(e.ground->>'melee')::integer+(e.ground->>'tank')::integer+(e.embarked->>'ranged')::integer+(e.embarked->>'melee')::integer+(e.embarked->>'tank')::integer;
 update public.empire set ground=e.ground,embarked=e.embarked,minerals=e.minerals-cm,energy=e.energy-ce,supplies=e.supplies-cs,loot=e.loot,troops=e.troops,ships=e.ships,mine=e.mine,reactor=e.reactor,farm=e.farm,defense=e.defense,tech=e.tech,collected_at=now(),attack_at=e.attack_at,shield_until=e.shield_until where id=uid;
 select jsonb_build_object(
  'unit_catalog',private.unit_catalog()->me.faction,
  'commander',(select to_jsonb(c) from public.commanders c where id=uid),
  'empire',(select to_jsonb(x) from public.empire x where id=uid),
  'ranking',coalesce((select jsonb_agg(to_jsonb(r)) from (select c.*,x.shield_until from public.commanders c join public.empire x using(id) order by c.elo desc,c.created_at limit 100) r),'[]'::jsonb),
  'reports',coalesce((select jsonb_agg(to_jsonb(b)) from (select * from public.battles where attacker=uid or defender=uid order by created_at desc limit 30) b),'[]'::jsonb),
  'last_battle',report,'server_time',now()) into result;
 return result;
end; $$;

revoke all on function private.valid_units(jsonb),private.unit_catalog(),private.army_power(jsonb,text,integer,boolean) from public,anon,authenticated;
-- Check constraints need this pure validation helper; no privileged reads.
grant execute on function private.valid_units(jsonb) to authenticated;

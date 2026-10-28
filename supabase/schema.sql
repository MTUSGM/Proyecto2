-- NEXUM: server-authoritative game. Apply once to a fresh Supabase project.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;
create table public.commanders (
 id uuid primary key references auth.users(id) on delete cascade,
 name text not null check(char_length(name) between 3 and 24),
 planet text not null check(char_length(planet) between 3 and 32),
 faction text not null check(faction in ('imperio','orkos','herejes')),
 elo integer not null default 1000 check(elo >= 0),
 wins integer not null default 0, battles integer not null default 0,
 created_at timestamptz not null default now()
);
create index commanders_ranking on public.commanders(elo desc);
create table public.empire (
 id uuid primary key references public.commanders(id) on delete cascade,
 minerals numeric not null default 1200 check(minerals >= 0),
 energy numeric not null default 900 check(energy >= 0),
 supplies numeric not null default 800 check(supplies >= 0),
 loot integer not null default 0,
 troops integer not null default 40 check(troops >= 0),
 ships integer not null default 2 check(ships >= 0),
 mine integer not null default 1, reactor integer not null default 1,
 farm integer not null default 1, defense integer not null default 1,
 tech integer not null default 1,
 collected_at timestamptz not null default now(),
 attack_at timestamptz, shield_until timestamptz not null default now() + interval '10 minutes'
);
create table public.battles (
 id uuid primary key default gen_random_uuid(),
 attacker uuid not null references public.commanders(id) on delete cascade,
 defender uuid references public.commanders(id) on delete set null,
 report jsonb not null, created_at timestamptz not null default now()
);
create index battles_attacker on public.battles(attacker,created_at desc);
create index battles_defender on public.battles(defender,created_at desc);
alter table public.commanders enable row level security;
alter table public.empire enable row level security;
alter table public.battles enable row level security;
revoke all on public.commanders, public.empire, public.battles from anon, authenticated;
grant select on public.commanders, public.empire, public.battles to authenticated;
create policy commanders_read on public.commanders for select to authenticated using (true);
create policy empire_read on public.empire for select to authenticated using (id=(select auth.uid()));
create policy battles_read on public.battles for select to authenticated using (attacker=(select auth.uid()) or defender=(select auth.uid()));

-- Privileged engine lives outside exposed schemas. All entry points require auth.uid().
-- Advisory transaction lock serializes this small MVP's mutations, including PvP.
create function private.game(action text, payload jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
 uid uuid := auth.uid(); me public.commanders; e public.empire; enemy public.commanders; d public.empire;
 n integer; target uuid; kind text; cm numeric:=0; ce numeric:=0; cs numeric:=0; lvl integer;
 elapsed numeric; atk numeric; def numeric; roll numeric; won boolean; lost integer; dlost integer:=0;
 delta integer:=0; reward integer:=0; sent integer; label text; result jsonb; report jsonb; npc integer;
begin
 if uid is null then raise exception 'Inicia sesión para jugar.'; end if;
 if action not in ('state','create','recruit','ship','upgrade','attack') or action is null then raise exception 'Acción inválida.'; end if;
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
  cm:=n*10; cs:=n*8; if me.faction='orkos' then cm:=cm*0.8; cs:=cs*0.8; end if;
  e.troops:=e.troops+n;
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
  sent:=(payload->>'troops')::integer;
  if sent is null or sent<1 or sent>e.troops or sent>e.ships*30 then raise exception 'Tropas insuficientes o capacidad de transporte superada (30 por nave).'; end if;
  cs:=sent*2; ce:=25*ceil(sent/30.0);
  if payload->>'target' is not null then
   target:=(payload->>'target')::uuid;
   if target=uid then raise exception 'No puedes atacar tu propio planeta.'; end if;
   select * into enemy from public.commanders where id=target;
   select * into d from public.empire where id=target for update;
   if enemy.id is null then raise exception 'Objetivo inexistente.'; end if;
   if d.shield_until>now() then raise exception 'Este planeta tiene un escudo temporal. Elige otro objetivo.'; end if;
   def:=(d.troops*10*(1+(d.tech-1)*0.15)+d.defense*100+d.ships*15)*(case when enemy.faction='imperio' then 1.15 else 1 end);
   label:=enemy.planet;
  else
   npc:=(payload->>'npc')::integer;
   if npc is null or npc not between 1 and 3 then raise exception 'Selecciona un nido tiránido válido.'; end if;
   def:=case npc when 1 then 250 when 2 then 750 else 1800 end;
   label:=case npc when 1 then 'Nido Caronte' when 2 then 'Colmena Vesper' else 'Leviatán IX' end;
  end if;
  atk:=sent*10*(1+(e.tech-1)*0.15)*(case when me.faction='orkos' then 1.1 else 1 end)+ceil(sent/30.0)*20;
  roll:=0.85+random()*0.3;
  won:=atk*roll>=def;
  lost:=least(sent,greatest(1,ceil(sent*(case when won then 0.12 else 0.35 end))::integer));
  e.troops:=e.troops-lost;
  if target is not null then
   dlost:=least(d.troops,ceil(sent*(case when won then 0.2 else 0.08 end))::integer);
   delta:=round(32*((case when won then 1 else 0 end)-1/(1+power(10::numeric,(enemy.elo-me.elo)/400.0))))::integer;
   -- Transfer conserves rating even at the zero floor.
   delta:=greatest(-me.elo,least(enemy.elo,delta));
   reward:=case when won then least(300,floor(d.minerals*0.1)::integer) else 0 end;
   update public.empire set troops=troops-dlost,minerals=minerals-reward,shield_until=now()+interval '10 minutes' where id=target;
   update public.commanders set elo=elo-delta,battles=battles+1,wins=wins+case when won then 0 else 1 end where id=target;
  else reward:=case when won then npc*180 else 0 end; end if;
  e.minerals:=least(20000,e.minerals+reward);
  e.loot:=e.loot+case when won then (case when me.faction='herejes' then 15 else 10 end)*coalesce(npc,1) else 0 end;
  e.attack_at:=now(); e.shield_until:=now();
  update public.commanders set elo=elo+delta,battles=battles+1,wins=wins+case when won then 1 else 0 end where id=uid;
  report:=jsonb_build_object('attacker_name',me.name,'defender_name',coalesce(enemy.name,'Tiránidos'),'target',label,'won',won,'sent',sent,'lost',lost,'defender_lost',dlost,'attack_power',round(atk),'defense_power',round(def),'roll',round(roll,3),'reward',reward,'elo_delta',delta,'pvp',target is not null);
  insert into public.battles(attacker,defender,report) values(uid,target,report);
 end if;
 if e.minerals<cm or e.energy<ce or e.supplies<cs then raise exception 'Recursos insuficientes.'; end if;
 update public.empire set minerals=e.minerals-cm,energy=e.energy-ce,supplies=e.supplies-cs,loot=e.loot,troops=e.troops,ships=e.ships,mine=e.mine,reactor=e.reactor,farm=e.farm,defense=e.defense,tech=e.tech,collected_at=now(),attack_at=e.attack_at,shield_until=e.shield_until where id=uid;
 select jsonb_build_object(
  'commander',(select to_jsonb(c) from public.commanders c where id=uid),
  'empire',(select to_jsonb(x) from public.empire x where id=uid),
  'ranking',coalesce((select jsonb_agg(to_jsonb(r)) from (select c.*,x.shield_until from public.commanders c join public.empire x using(id) order by c.elo desc,c.created_at limit 100) r),'[]'::jsonb),
  'reports',coalesce((select jsonb_agg(to_jsonb(b)) from (select * from public.battles where attacker=uid or defender=uid order by created_at desc limit 30) b),'[]'::jsonb),
  'last_battle',report,'server_time',now()) into result;
 return result;
end; $$;
revoke all on function private.game(text,jsonb) from public,anon,authenticated;
grant execute on function private.game(text,jsonb) to authenticated;
create function public.game(action text, payload jsonb default '{}'::jsonb)
returns jsonb language sql security invoker set search_path='' as $$ select private.game(action,payload); $$;
revoke all on function public.game(text,jsonb) from public,anon;
grant execute on function public.game(text,jsonb) to authenticated;

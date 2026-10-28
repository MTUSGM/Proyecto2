# NEXUM — Proyecto2

Juego web de estrategia espacial en español, inspirado en Warhammer 40.000. Proyecto académico no oficial, sin afiliación a Games Workshop. Interfaz responsive con Vite y JavaScript, autenticación y motor transaccional PostgreSQL en Supabase, hosting en Vercel.

## Jugar

Crea una cuenta, confirma el correo y elige Orkos, Imperio o Herejes. Funda un planeta, recluta tropas, construye transportadores y mejora infraestructura. Ataca tres nidos tiránidos o planetas de otros jugadores. Todos conservan su planeta.

- Recursos iniciales: 1.200 minerales, 900 energía, 800 suministros; 40 unidades a distancia; 2 naves; 1.000 Elo.
- Producción: 120/90/75 por hora por nivel (minerales/energía/suministros). Acumulación offline hasta 24 h y 20.000 unidades por recurso.
- Orkos: tropas 20% más baratas y +10% poder de tropas al atacar. Imperio: +15% defensa. Herejes: +50% botín. El botín es una puntuación acumulada; no es moneda gastable en esta versión.
- Cada nave ofrece 30 plazas (infantería: 1; tanque: 5) y aporta 20 poder si se utiliza. La investigación añade 15% poder de tropas por nivel adicional.
- Combate instantáneo, poder atacante con factor aleatorio de 0,85 a 1,15. Bajas atacantes: 12% al ganar, 35% al perder, redondeadas arriba. Las naves regresan siempre.
- Coste de ataque: 2 suministros/tropa, 25 energía/nave utilizada. Reagrupación: 60 s.
- Elo: fórmula estándar con K=32, solo PvP, suma conservada y mínimo cero. Los NPC no alteran Elo.
- Escudo: 10 min al crear planeta o recibir ataque. Atacar desactiva el escudo propio.
- PvP: el ganador roba hasta 10% de minerales del defensor, máximo 300. PvE: 180/360/540 minerales por victoria.
- Mejoras hasta nivel 10. Reclutamiento, construcción y mejoras instantáneos.

## Desarrollo

```sh
npm ci
cp .env.example .env.local
# Completar URL y clave publishable de Supabase
npm run dev
npm test
npm run build
```

Node 22.12+ o 24. Dependencias fijadas en package-lock.json. Nunca usar una service_role key en VITE_*.

## Base de datos

`supabase/schema.sql` contiene el esquema inicial completo aplicado con la migración remota `nexum_game`. Para una nueva instalación, ejecútalo una sola vez en un proyecto vacío. No volver a aplicarlo sobre la instalación existente.

`public.commanders` contiene perfiles públicos autenticados. `public.empire` y `public.battles` usan RLS para que cada usuario lea solo su estado e informes. No hay permisos INSERT/UPDATE/DELETE de clientes. `public.game` es una función invoker que llama al motor validado `private.game` (definer, search_path vacío, auth.uid obligatorio y permisos explícitos). Las compras, recursos, azar, bajas y Elo se calculan en PostgreSQL. La app solo envía intenciones.

Las mutaciones usan un advisory lock transaccional global: adecuado para el MVP, pero antes de alta concurrencia debe sustituirse por bloqueos de filas en orden consistente. Ranking y objetivos muestran los primeros 100 comandantes. Informes: últimos 30 por usuario.

`tests/database.sql` conserva la prueba de la versión inicial; para la versión actual ejecutar `tests/units.sql` dentro de BEGIN/ROLLBACK. La prueba inicial verifica creación, reclutamiento, costes, validación, mejoras, naves, PvE, cooldown, PvP, Elo, persistencia del planeta, acumulación offline, RLS, RPC autenticado y rechazo de acceso sin sesión. Ejecutar en staging con permisos de administración. Usa fixtures temporales y ROLLBACK, sin dejar cuentas ni partidas de prueba.

## Despliegue Vercel

Framework Vite; build `npm run build`; salida `dist`. Variables por entorno:
- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_PUBLISHABLE_KEY`

En Supabase Authentication > URL Configuration configurar Site URL con la URL del despliegue, y añadirla a Redirect URLs (también localhost:5173 para desarrollo). Es necesario para confirmación por correo y recuperación de contraseña. Configurar SMTP propio antes de una apertura pública con muchos usuarios; el proveedor de correo predeterminado tiene límites.

Para despliegues automáticos instalar la integración GitHub en Vercel y conectar MTUSGM/Proyecto2, rama main. El despliegue inicial se puede subir directamente por API sin esa integración.

## Verificaciones

- `npm test`: reglas de interfaz, transporte, facciones e inyección HTML.
- `npm run build`: bundle de producción.
- `tests/database.sql`: flujo completo de motor y autorización.
- Supabase Security Advisors: revisar después de modificar el esquema.

No contiene pagos, compras reales, conquista permanente, colas de construcción ni combates animados. El objetivo es una primera versión jugable con persistencia real.


## Tropas y embarque (v2)

Después de `supabase/schema.sql`, aplicar una sola vez `supabase/units_upgrade.sql`. La migración conserva la cantidad exacta de tropas existentes como unidades a distancia, en tierra. Los informes históricos se conservan.

Cada facción tiene infantería a distancia, cuerpo a cuerpo y tanques. `src/units.json` documenta los nueve perfiles; el motor devuelve su catálogo autoritativo con `game('state')`. Ataque/defensa son distintos, el blindaje reduce la fracción de bajas y los tanques ocupan 5 plazas. Los valores se muestran antes del reclutamiento.

`empire.ground` contiene la guarnición y `empire.embarked` la flota persistente. `troops` se mantiene como total agregado para compatibilidad. `game('embark', {units:{ranged,melee,tank}})` fija la composición total embarcada, valida disponibilidad y capacidad, y transfiere unidades atómicamente. Enviar ceros desembarca todo. Reclutar siempre añade a tierra.

El planificador muestra el poder atacante y la defensa que permanecerá en el planeta. Guardar el embarque es necesario antes de atacar; después de combatir, los supervivientes permanecen embarcados. Las naves no aportan defensa planetaria. Solo `ground` participa y sufre bajas en la defensa. Los combates siguen siendo instantáneos, con 60 s de reagrupación.

Ataque: suma de ataques × tecnología × bonus de facción + 20 por transporte utilizado. Defensa: (suma de defensas terrestres × tecnología + 100 por nivel de bastión) × bonus imperial. La fracción de bajas atacantes es 12% al ganar, 35% al perder; la defensora es 30% si el atacante gana, 10% si pierde. Por tipo: ceil(cantidad × fracción × (1 − blindaje/100)), sin superar la cantidad disponible. Los costes de suministros dependen de la unidad; energía = 25 × ceil(plazas utilizadas/30).

Pruebas v2: `npm test`, `npm run build` y `tests/units.sql` dentro de una transacción con ROLLBACK. Verifican reclutamiento, costes, conservación, capacidad, entradas inválidas, atomicidad, desembarque, PvE/PvP, defensa solo terrestre, bajas por blindaje, Elo y aislamiento RLS.


## Estrategia orbital y nidos (v3)

Aplicar `supabase/orbital_upgrade.sql` después de `units_upgrade.sql`. Las naves existentes se convierten en transportes armados, sin perder capacidad. `src/strategy.json` documenta los catálogos del servidor; el estado devuelve `ship_catalog`, `npc_catalog` y `all_units`.

- Transporte armado: 30 plazas, 12 ataque orbital, 12 defensa orbital, 1 apoyo terrestre. Construcción: 300 minerales, 200 energía, 40 suministros. Salida: 25 energía y 5 suministros.
- Fragata de combate: 10 plazas, 120 ataque orbital, 100 defensa orbital, 6 apoyo terrestre. Construcción: 600 minerales, 400 energía, 100 suministros. Salida: 70 energía y 15 suministros.
- Baterías orbitales: +80 defensa por nivel, hasta 10. Se suman a las naves de reserva, excluyendo las asignadas a expedición.
- La expedición fija tropas y naves en un solo `embark`. Las tropas terrestres defienden el suelo; las naves no asignadas defienden la órbita. Liberar la flota devuelve tropas a tierra y todas las naves a reserva.
- Distancia contrarresta cuerpo a cuerpo; cuerpo a cuerpo con cargas antiblindaje contrarresta tanques; tanques contrarrestan distancia. Bono +50% contra la clase favorable y penalización −25% contra la desfavorable, ponderados por las plazas del ejército enemigo. Se aplica en ataque y defensa.
- Primero se resuelve la órbita con azar ±15%. Si falla, no hay combate terrestre y no se daña la guarnición; el atacante pierde una fracción de tropas transportadas y se retira. Si pasa, se calculan bajas orbitales y luego combate terrestre con otro azar ±15%.
- Apoyo naval terrestre: limitado al 25% del ataque de las tropas desembarcadas. No permite reemplazar el ejército con solo fragatas.
- Las naves regresan siempre y no se destruyen en esta versión. Cada salida cobra reparación en energía según resistencia orbital y número de naves, además de combustible y suministros. Las tropas sí pueden morir en órbita y en tierra. El planificador muestra el coste antes de atacar.
- Los NPC usan Termagantes, Hormagantes y Carnifex; Caronte (20/10/0, órbita 20), Vesper (15/45/2, órbita 160), Leviatán (30/15/10, órbita 360 y tecnología 2). Se regeneran por incursión y no se conquistan. Solo PvP modifica Elo.

`tests/orbital.sql` es la prueba de integración de la versión actual. Ejecuta fixtures y rollback; las suites SQL anteriores son históricas y requieren su esquema correspondiente. `tests/strategy.test.mjs` verifica capacidad, ventajas de composición, NPC y apoyo limitado. `tests/ui.test.mjs` comprueba el renderizado y navegación del cliente con datos de prueba, sin modificar cuentas reales.

# NEXUM — Proyecto2

Juego web de estrategia espacial en español, inspirado en Warhammer 40.000. Proyecto académico no oficial, sin afiliación a Games Workshop. Interfaz responsive con Vite y JavaScript, autenticación y motor transaccional PostgreSQL en Supabase, hosting en Vercel.

## Jugar

Crea una cuenta, confirma el correo y elige Orkos, Imperio o Herejes. Funda un planeta, recluta tropas, construye transportadores y mejora infraestructura. Ataca tres nidos tiránidos o planetas de otros jugadores. Todos conservan su planeta.

- Recursos iniciales: 1.200 minerales, 900 energía, 800 suministros; 40 tropas; 2 naves; 1.000 Elo.
- Producción: 120/90/75 por hora por nivel (minerales/energía/suministros). Acumulación offline hasta 24 h y 20.000 unidades por recurso.
- Orkos: tropas 20% más baratas y +10% poder de tropas al atacar. Imperio: +15% defensa. Herejes: +50% botín. El botín es una puntuación acumulada; no es moneda gastable en esta versión.
- Cada nave transporta 30 tropas y aporta 20 poder si se utiliza. La investigación añade 15% poder de tropas por nivel adicional.
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

`tests/database.sql` verifica creación, reclutamiento, costes, validación, mejoras, naves, PvE, cooldown, PvP, Elo, persistencia del planeta, acumulación offline, RLS, RPC autenticado y rechazo de acceso sin sesión. Ejecutar en staging con permisos de administración. Usa fixtures temporales y ROLLBACK, sin dejar cuentas ni partidas de prueba.

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

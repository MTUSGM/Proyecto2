# Informe: autenticación, Realtime y tiempos del juego

Fecha: 8 de noviembre de 2026. Repositorio: MTUSGM/Proyecto2.

**Estado: migración aplicada con autorización expresa del usuario, PR #1 fusionada y aplicación desplegada en producción (READY).** Se verificaron ataques y contraataques reales mediante dos clientes independientes. La confirmación de correo y la medición completa servidor → pantalla siguen pendientes.

## A. Cambios implementados

- Confirmación de contraseña en registro y cambio de contraseña. Validación de coincidencia y correo con dominio; mensajes de autenticación en español. Se conserva el flujo de enlace de confirmación de Supabase, ya activado en la configuración real. No se almacenan contraseñas fuera de Supabase Auth.
- Un canal Realtime por sesión. Suscripciones privadas a imperio propio, notificaciones propias e informes de ataques propios; revisión pública de comandantes para las defensas y clasificación ya visibles en la galaxia. Limpieza al salir y resincronización al reconectar, recuperar conectividad o volver a la pestaña.
- Respaldo cada 120 segundos, solo con sesión. Eventos de una misma operación agrupados durante 120 ms; consultas de estado concurrentes consolidadas y respuestas anteriores a una mutación descartadas.
- Actualización del DOM conservando nodos de formulario, valores, foco y edición. Los campos activos, borradores de flota y modales ya no bloquean la recepción de eventos.
- Notificaciones persistidas por batalla, destinatario y atacante; lectura persistente y acción «Contraatacar». Esta acción selecciona el atacante en el planificador, sin ejecutar un ataque; se mantienen las validaciones del servidor.
- Configuración de tiempos entregada por el servidor. Reloj de interfaz ajustado con server_time y actualización de botones al vencer escudos o espera, sin aguardar al polling.
- Consulta de estado sin escritura de recursos: evita ciclos Realtime → consulta → escritura → Realtime. Producción calculada para la respuesta y materializada al ejecutar acciones.
- UUID de petición e índice único para detectar la repetición de una misma orden de ataque; conservación de la transacción y bloqueo del motor existente.

## B. Archivos

| Archivo | Función |
|---|---|
| src/main.js | Registro, sincronización híbrida, conservación de formularios, avisos, contraataque, reloj y producción visual |
| src/style.css | Presentación adaptable de notificaciones |
| package.json y package-lock.json | morphdom fijado; PGlite y jsdom para pruebas locales |
| supabase/migrations/20261108163806_realtime_auth_speed.sql | Migración aplicada en Supabase |
| tests/ui.test.mjs | Actualiza el entorno simulado para Realtime |
| tests/sync.test.mjs | DOM real en jsdom: foco, valores, agrupación, reconexión, respaldo, cierre de sesión, confirmación de contraseña |
| tests/migration.test.mjs | PostgreSQL local PGlite: migración de datos, RLS, avisos, tiempos, deduplicación y producción |
| .gitignore | Excluye archivos temporales del CLI de Supabase |
| docs/verification-realtime.md | Este informe y límites de verificación |

## C. Supabase

Inspección real: proyecto xpyuzrhxejitmiyobqqb, activo. Dos comandantes, dos imperios y dos batallas existentes; ningún escudo ni cooldown activo al inspeccionar. Las tres tablas existentes tienen RLS. Ninguna estaba incluida en supabase_realtime.

Migración aplicada:

- Nueva tabla attack_notifications con id de batalla único, destinatario, atacante, nombre, planeta, resultado, fecha y read_at.
- SELECT únicamente del destinatario; UPDATE únicamente de la columna read_at y de filas propias. Sin INSERT/DELETE desde clientes.
- Trigger privado notify_attack tras insertar una batalla PvP.
- state_version en commanders y trigger privado signal_empire_change que señala cambios tácticos del imperio sin publicar sus recursos privados.
- request_id en battles e índice único parcial por atacante/petición.
- Publicación de commanders, empire, battles y attack_notifications bajo las políticas RLS.
- Función privada game_timing y actualización del motor privado game. Se mantiene public.game como entrada SECURITY INVOKER y el motor con comprobación auth.uid().
- Liquidación de producción anterior con la tarifa original; reducción a la mitad del tiempo pendiente de escudos y cooldowns existentes. Sin borrado ni reinicio de partidas. Nueva producción desde el instante de migración.

La auditoría real inicial no encontró errores de RLS. Reportó protección contra contraseñas filtradas desactivada; no se modificó. Referencia: https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection . Los avisos de rendimiento fueron índices aún no usados; se conservaron.

## D. Autenticación real

| Usuario | Existe | Confirmado | Inicio de sesión por API | Visibilidad de imperios |
|---|---|---|---|---|
| prueba1@pruebaproy | Sí | Sí | Correcto | Solo su propio imperio |
| prueba2@pruebaproy | Sí | Sí | Correcto | Solo su propio imperio |

Se autenticaron clientes independientes con las credenciales proporcionadas, sin restablecerlas. Ambos perfiles están vinculados. Estas direcciones existentes son admitidas para iniciar sesión; al registrar cuentas nuevas se exige un dominio completo para poder recibir correo.

La configuración pública de Auth indica mailer_autoconfirm=false y registro habilitado. La recepción del correo, URL de retorno y apertura de un enlace nuevo no fueron verificadas: no se dispone de un buzón de prueba accesible. La prevención de duplicados permanece a cargo de Supabase Auth; falta verificar el flujo completo con correo real.

## E. Rendimiento

Antes: el código utilizaba polling de 30 segundos y omitía consultas mientras había un campo activo, un borrador de flota, un modal o una acción en curso. Es evidencia del código, no una medición de latencia entre usuarios.

Después: dos clientes autenticados independientes y conectados al Realtime real ejecutaron un ataque y un contraataque:

| Operación | Respuesta del ataque | Evento tras respuesta | Estado reconciliado tras respuesta |
|---|---:|---:|---:|
| prueba1 → prueba2 | 82 ms | 50 ms | 165 ms |
| prueba2 → prueba1 | 157 ms | 39 ms | 172 ms |

Son mediciones reales de clientes API, **no del renderizado en pantalla**. Los avisos estaban persistidos al consultar el estado y reenviar la misma petición fue rechazado en ambos casos. La prueba DOM local conserva el campo activo al recibir eventos simulados; no equivale a una prueba completa entre navegadores en producción.

## F. Tiempos

| Mecánica | Antes | Ahora |
|---|---:|---:|
| Espera entre ataques | 60 s | 30 s |
| Protección inicial y tras ataque | 10 min | 5 min |
| Producir 120 minerales por nivel | 1 h | 30 min (240/h) |
| Producir 90 energía por nivel | 1 h | 30 min (180/h) |
| Producir 75 suministros por nivel | 1 h | 30 min (150/h) |
| Límite temporal de producción sin conexión | 24 h | 12 h |
| Construcción, reclutamiento, mejoras, embarque y resolución de combate | Instantáneos | Instantáneos |
| Polling técnico | 30 s | 120 s (respaldo) |

El máximo de recursos acumulables por periodo offline se conserva: doble producción durante la mitad del tiempo. No existen actualmente colas temporizadas de construcción, viajes por coordenadas o investigación separada; no se añadieron mecánicas nuevas ni se alteraron timeouts de red o seguridad.

## G. Pruebas y resultados

- `npm test`: **16/16 pasan**.
- `npm run build`: correcto con las variables públicas del proyecto.
- Migración ejecutada íntegramente en PGlite local sobre esquema y mejoras originales. Detectó una ambigüedad de alias SQL, corregida antes de la última ejecución.
- SQL local: conservación de partidas y Elo, liquidación a tarifa anterior, reducción exacta de escudo/cooldown pendiente, rechazo de ataque a los 29 s y aceptación a los 30 s, duplicación de request_id rechazada, trigger de aviso único, lectura persistente, RLS por propietario, recursos privados inmodificables y producción al doble sin escrituras desde state.
- Pruebas originales de combate orbital ejecutadas también dentro del entorno PostgreSQL local antes de la migración.
- jsdom: un canal, polling de 120000 ms, eventos agrupados, mismo nodo de entrada y foco tras actualizar, valor en edición conservado, reconexión sin duplicados, recuperación de evento omitido por polling, contraataque abre planificador sin atacar y cierre de sesión detiene consultas.
- API real: dos inicios de sesión y aislamiento de lectura correctos.
- Respaldo real sin suscripción Realtime en el destinatario: se cometió un tercer ataque y el intervalo de 120000 ms recuperó exactamente un aviso nuevo. La respuesta llegó a los 123538 ms desde el inicio del intervalo, incluyendo red/consulta. Sin duplicados.
- RLS real de notificaciones: el atacante no pudo leer ni actualizar el aviso del destinatario (cero filas). El destinatario lo marcó leído y una sesión nueva conservó esa marca; no reapareció entre los avisos pendientes.
- Navegador cloud: formulario de registro desplegado inspeccionado; incluye correo, contraseña y confirmación de contraseña. La sesión autenticada en este navegador requeriría el flujo seguro interactivo, por lo que no se declaró una prueba autenticada completa de UI.
- Supabase tras migrar: cuatro tablas publicadas; dos imperios conservados; configuración del motor 30 s / 300 s / producción ×2 / límite offline 43200 s. Advisors sin nuevos problemas de seguridad; permanece el aviso de contraseñas filtradas ya documentado.
- Vercel: consulta de errores de runtime del despliegue no devolvió registros. Es una aplicación estática; este resultado no sustituye la observación de errores del navegador.

## H. Despliegue

- Aplicación: https://proyecto2-nu-rust.vercel.app/
- PR fusionada: https://github.com/MTUSGM/Proyecto2/pull/1
- Commit de código: ce9daa3386e5885e54786ef1a82e268d818c7c5c (incluye 4daf16d4ef526d3d493a9898e1caf61fe66fddaa).
- Vercel: dpl_2bgk4PKEiDofVjAjk72B6LaAzrE9, producción, READY.
- URL del despliegue: https://proyecto2-23wnvcz0h-mtusgm.vercel.app . El alias público anterior fue abierto y mostró el formulario actualizado.

## I. Límites y pendientes

1. Medir servidor → pantalla con dos navegadores autenticados y comprobar visualmente ataques durante escritura, contraataque, reconexión y recarga. Hay evidencia real API y evidencia DOM local, pero no se declara una prueba de navegador completa.
2. Verificar registro, recepción y confirmación con un buzón accesible. El envío de confirmación está habilitado; no se ha observado la recepción de un correo nuevo.
3. Las pruebas reales usaron las mecánicas normales de ataque de los dos usuarios de prueba: consumen recursos y pueden causar bajas y cambios de Elo. Se conservaron los informes, sin borrar registros ni reiniciar partidas.

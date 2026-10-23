# Plan por etapas — sesiones aisladas por servidor

**Estado:** propuesta, pendiente de implementación  
**Hallazgo:** BUG-009 en `Docs/bugs/AUDITORIA-INTEGRAL.md`  
**Prioridad:** P1

## Objetivo

Cada servidor guardado debe restaurar solo la cuenta/token asociado a su URL canónica. Cambiar de servidor no debe reutilizar credenciales de otra instancia ni borrar sus credenciales al cerrar sesión.

## Etapa 1 — Definir identidad y compatibilidad

- Definir clave estable del servidor: URL normalizada sin slash final, con esquema y puerto preservados.
- Crear un modelo de sesión por servidor (token, userId, userName), almacenado en Keychain; no guardar tokens en UserDefaults.
- Detectar las claves globales existentes como formato legacy.
- Migrar las claves legacy únicamente al servidor que coincide con `KeychainKey.serverURL`; no copiarlas a otros servidores.
- Mantener rollback: si falla la escritura de la sesión nueva, conservar intactas las claves legacy y mostrar error.

## Etapa 2 — Carga y cambio de servidor

- Separar estados de `AuthModel`: sesión activa, restaurando, requiere login y error de red temporal.
- Al seleccionar un servidor, invalidar `LibraryModel` y cualquier estado de cuenta dependiente del servidor antes de mostrar biblioteca.
- Cargar sesión por URL y validar con `/Users/{id}`.
- Un 401 elimina solo la sesión de ese servidor; un timeout/desconexión no borra credenciales válidas ni fuerza logout destructivo.
- Login guarda la sesión en el espacio de servidor y construye la biblioteca con esa sesión.

## Etapa 3 — Logout, eliminación y aislamiento de estado

- Logout elimina solo la sesión del servidor actual.
- Borrar un servidor elimina su sesión asociada; el resto de servidores y sesiones permanece.
- Revisar que preferencias no sensibles, historial, discovery y estados del reproductor no se reutilicen cruzando servidor/usuario.
- Evitar conservar pantallas o tareas de la biblioteca anterior durante el cambio.

## Etapa 4 — Pruebas y migración

- Unidad: normalización de URL, lookup de sesión, migración legacy, rollback de Keychain.
- Modelo/UI: cambiar A→B→A con usuarios distintos; B sin credenciales; token B inválido; fallo de red al validar; logout; eliminar servidor.
- Verificar que no se envía token A a host B en ninguna solicitud.
- Ejecutar `swift test` y compilar iOS, macOS, tvOS y visionOS.
- Probar con dos instancias Jellyfin de staging antes de publicar.

## Criterios de aceptación

- El token enviado siempre corresponde al host elegido.
- A→B→A restaura la sesión correcta de A sin volver a autenticar si sigue válida.
- Un error de red no elimina sesión ni historial.
- Un 401 limpia solo la cuenta afectada.
- Logout y eliminación no alteran credenciales de otros servidores.
- Ninguna biblioteca anterior queda visible después de seleccionar otro servidor.

## Riesgos

- Migrar una clave legacy a un servidor incorrecto si la URL actual no coincide de forma canónica.
- Cambios parciales de Keychain pueden dejar sesión nueva incompleta; migración debe ser idempotente.
- `AuthModel` hoy se instancia sin servidor; habrá que introducir una frontera por servidor sin duplicar estado global de UI.
- Validación remota al seleccionar servidor requiere estados claros cuando el backend está offline.

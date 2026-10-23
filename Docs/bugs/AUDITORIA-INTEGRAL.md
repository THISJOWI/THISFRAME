# Auditoría integral de THISJELLYFIX / THISFRAME

**Estado:** en curso  
**Inicio:** 2026-10-23  
**Alcance:** revisión estática de módulos, navegación, reproducción, red, persistencia, UX y pruebas; validación dinámica disponible en este entorno.

## Resumen de estado

La auditoría sigue abierta: el proyecto incluye cambios locales sin commit en `Package.swift`, `DetailView.swift`, `PlayerView.swift`, `PlayerViewModel.swift`, `JellyfinPlaybackClient.swift`, `AVPlaybackEngine.swift` y dos suites nuevas. Esos cambios se consideran trabajo del usuario y no se sobrescriben. Los hallazgos referidos a esas áreas deben revisarse contra el estado local actual y no contra una base limpia.

No se ha confirmado ningún P0/P1 durante esta pasada inicial. Hay una incidencia P2 confirmada por inspección en búsqueda. El informe previo `Docs/bugs/2026-09-25-investigation.md` registra investigaciones históricas de PiP y progreso, y `PLAN-AUDITORIA-CORRECCIONES.md` registra riesgos históricos de concurrencia del reproductor; se preservan como antecedente, pero su estado debe cotejarse con los cambios actuales y no se presentan como regresiones vigentes sin nueva prueba.

Se confirmó e implementó también BUG-004 (estantes que conservaban datos tras una respuesta vacía), con una prueba de regresión añadida. Se confirmó BUG-005 en la cancelación de descargas. BUG-003 y BUG-005 siguen pendientes.

## Inventario de incidencias

### BUG-003 — La búsqueda presenta fallos de red como “sin resultados”

- **Prioridad:** P2 — Medio.
- **Categoría:** Estados de error / búsqueda / UX.
- **Archivos implicados:** `Sources/ThisJellyFixFeature/SearchView.swift`, propiedad `body`, `onChange(of: query)`.
- **Evidencia:** líneas 171–188 gestionan el error de `libraryClient.searchItems` con `catch`, vacían `results` y no guardan ningún error. Las líneas 68–78 muestran “Sin resultados para…” cuando ambos arrays están vacíos, sin distinguir error HTTP, desconexión o cero coincidencias.
- **Reproducción:** con sesión iniciada, escribir una consulta de al menos dos caracteres y hacer que el servidor no responda o devuelva un error. La vista termina mostrando el estado de cero resultados.
- **Actual / esperado:** actual: el fallo se representa como búsqueda correcta sin coincidencias; esperado: estado de error con opción de reintentar, manteniendo distinto el caso de respuesta vacía válida.
- **Causa y certeza:** causa confirmada por inspección; no requiere hipótesis.
- **Solución propuesta:** almacenar el estado de error de la búsqueda local; mostrar mensaje y acción de reintento, y limpiar el error al cambiar consulta o al completar una petición válida.
- **Riesgo / pruebas:** bajo. Probar respuesta vacía 200, error de transporte, HTTP no exitoso, cambio de consulta durante una petición y reintento. No se aplicó una corrección todavía.
- **Impacto esperado:** evita que el usuario concluya que el contenido no está en su biblioteca cuando el servicio está temporalmente inaccesible.
- **Estado:** pendiente de corrección.

### BUG-004 — Los estantes conservan elementos tras una respuesta vacía válida

- **Prioridad:** P2 — Medio.
- **Categoría:** Frescura de biblioteca / estados inconsistentes.
- **Archivos implicados:** `Sources/ThisJellyFixFeature/LibraryModel.swift`, `loadRow(_:_:)` y `publish(_:)`.
- **Evidencia:** `loadRow` invoca `publish` también cuando el servidor responde correctamente con `[]`; `publish` hacía `guard !row.items.isEmpty else { return }` antes de retirar el valor anterior. Por ello, el refresh exitoso vacío dejaba en pantalla la fila de la carga previa.
- **Reproducción:** cargar una biblioteca con elementos en “Últimos agregados”, retirar esos elementos del conjunto que devuelve el servidor y recargar. Las filas de datos todavía presentes se actualizaban, pero la fila vacía seguía conservando su snapshot anterior.
- **Actual / esperado:** actual: respuesta vacía no reemplaza ni elimina el contenido anterior; esperado: respuesta vacía válida elimina la fila obsoleta. Los errores de red deben conservar el dato anterior, porque en ese caso `publish` no se llama.
- **Causa y certeza:** causa confirmada directamente en el orden de las instrucciones.
- **Solución aplicada:** `publish` ahora retira el snapshot previo y solo añade una nueva fila si tiene contenido.
- **Riesgo / pruebas:** bajo. Prueba de regresión añadida en `LibraryModelCategoryTests`, que carga contenido, cambia la respuesta a vacía y comprueba que la fila desaparezca. La suite completa aún está ejecutándose.
- **Impacto esperado:** las eliminaciones, elementos reproducidos o cambios de biblioteca reflejan el estado real tras una carga correcta.

### BUG-005 — La cancelación de una descarga borra el estado local aunque falle el servicio

- **Prioridad:** P2 — Medio.
- **Categoría:** Integración *arr / feedback / persistencia de acciones.
- **Archivos implicados:** `Sources/ThisJellyFixDiscovery/DownloadCoordinator.swift`, `removeEntries(matching:)` (líneas aproximadas 242–258); `Sources/ThisJellyFixFeature/DownloadsView.swift`, acciones “Quitar” y “Descartar”.
- **Evidencia:** la eliminación remota usa `try?` y el resultado se ignora; después el coordinador quita todas las coincidencias locales, persiste y refresca. Si la llamada DELETE falla, la fila puede desaparecer temporalmente mientras la orden siga en Radarr/Sonarr. El UI no recibe error de cancelación y el banner existente solo refleja `lastRefreshError`.
- **Reproducción:** intentar quitar una orden mientras el servicio está inaccesible o devuelve HTTP no exitoso; observar que el elemento se elimina de la lista local sin mensaje de fallo.
- **Actual / esperado:** actual: el clic aparenta cancelar aunque el servidor no haya confirmado la cancelación; esperado: conservar/recuperar la entrada y mostrar el rechazo/error.
- **Causa y certeza:** confirmada en el manejo explícito del error; la visibilidad final depende del siguiente refresh exitoso.
- **Solución propuesta:** no retirar silenciosamente las entradas cuyo DELETE falla; devolver un resultado/error al modelo de UI, mostrar feedback y refrescar para reconciliar respuestas parciales cuando hay varias coincidencias.
- **Riesgo / pruebas:** medio porque una cancelación puede coincidir con aceptación remota aunque el cliente pierda la respuesta. Probar éxito, error HTTP, timeout y fallo parcial de varias coincidencias, verificando idempotencia del retry.
- **Impacto esperado:** una acción destructiva comunica su resultado correctamente y la lista no miente sobre el estado del servicio.
- **Estado:** pendiente.

## Riesgos en investigación

### RISK-001 — Concurrencia/orden de informes de reproducción

El plan existente describe riesgo de progreso y parada concurrentes. Como `PlayerViewModel.swift` y `JellyfinPlaybackClient.swift` están modificados localmente, hay que comprobar la solución actual y ejecutar sus nuevas pruebas antes de clasificarlo como abierto o resuelto. No se cuenta como incidencia vigente todavía.

### RISK-002 — Solicitudes de segmentos concurrentes

El plan existente describe potencial de peticiones periódicas solapadas. Requiere cotejar `PlayerViewModel.swift` actual, confirmar cancelación/invalidez al cambiar de elemento y probar una respuesta retenida. No se cuenta como incidencia vigente todavía.

### RISK-003 — Aislamiento de concurrencia de delegates y almacenamiento de preferencias

La compilación SwiftPM produjo warnings de `Sendable` para `IntegrationConfig` y `SubtitleProviderStore`, que guardan `UserDefaults` en structs conformes a `Sendable`. La compilación iOS también advirtió que la conformidad de `PipCoordinator` a `AVPictureInPictureControllerDelegate` cruza requisitos no aislados con métodos main-actor; Swift 6 lo elevará a error según el diagnóstico del compilador. Son riesgos reales de migración y merecen resolver explícitamente la frontera de actor, pero las advertencias actuales no prueban por sí solas una carrera observable en Swift 5.10. Validar la cola de callbacks que entrega AVKit antes de elegir aislamiento o `@preconcurrency`.

## Cobertura y estado de validación

- **Estructura y límites de módulos:** revisados de forma inicial; SwiftPM separa Core, Networking, Discovery, Playback y Feature. El target Cast solo está en el proyecto Xcode, conforme a las instrucciones del repo.
- **Navegación y autenticación:** inspección parcial de `RootView` y `AuthModel`; la sesión se restaura desde Keychain y valida token de forma asíncrona en `restoreSession` cuando es llamada. Falta verificar sus flujos y plataformas.
- **Búsqueda:** inspección estática, hallazgo BUG-003 confirmado.
- **Vaciamiento de filas al refrescar:** corregido y con prueba de regresión añadida (BUG-004).
- **Descargas:** inspección de cancelación confirmó un fallo de feedback/estado (BUG-005).
- **Reproducción, sincronización, PiP, AirPlay y Next Up:** requiere auditoría detallada; parte afectada por cambios locales.
- **Pruebas:** `swift test` compiló y ejecutó **278 tests, 0 fallos**; incluyó la prueba nueva de BUG-004. La suite focalizada `LibraryModelCategoryTests` pasó **3/3**.
- **Compilaciones Xcode/plataformas:** `thisjellyfix-iOS` para iOS Simulator, `thisjellyfix-macOS` y `thisjellyfix-tvOS` pasaron (`BUILD SUCCEEDED`); compilación visionOS en curso. Las builds emitieron warnings de concurrencia en `Sendable`/delegate PiP y warnings de bindings sin uso. La build iOS Simulator requiere el SDK Google Cast 4.8.6 y GTMSessionFetcher 3.5.0; se resolvieron en `/tmp` sin tocar configuración del repo.
- **Servidor/dispositivos reales:** no disponibles en esta pasada; no se afirma validación de integración real.

## Recomendación UX/UI inicial

Priorizar estados diferenciados de carga, error, desconexión y cero resultados en las superficies que hoy consumen errores. La búsqueda es un caso confirmado; la consistencia del resto de pantallas aún está en revisión. No se recomienda un rediseño visual general: la inspección debe determinar primero si hay problemas verificables de jerarquía, legibilidad, accesibilidad o navegación.

## Próximos pasos

1. Reintentar la suite SwiftPM con la caché de módulos redirigida a una ubicación permitida y registrar resultado real.
2. Revisar los cambios locales del reproductor como código candidato, sin reescribirlos, contrastando con los riesgos históricos BUG-001/002.
3. Auditar clientes HTTP, errores y límites de tiempo; gestión de búsqueda, cargas y refresh de biblioteca; después detalles/favoritos/descargas.
4. Completar inspección por plataformas de `project.yml`, puntos de entrada y ramas condicionales; compilar destinos disponibles si el entorno lo permite.
5. Añadir nuevas incidencias con evidencia y certeza explícitas; solo entonces corregir P1 y P2 razonables y validables.

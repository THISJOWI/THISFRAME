# Auditoría integral de THISJELLYFIX / THISFRAME

**Estado:** en curso  
**Inicio:** 2026-10-23  
**Alcance:** revisión estática de módulos, navegación, reproducción, red, persistencia, UX y pruebas; validación dinámica disponible en este entorno.

## Resumen de estado

La auditoría sigue abierta: el proyecto incluye cambios locales sin commit en `Package.swift`, `DetailView.swift`, `PlayerView.swift`, `PlayerViewModel.swift`, `JellyfinPlaybackClient.swift`, `AVPlaybackEngine.swift` y dos suites nuevas. Esos cambios se consideran trabajo del usuario y no se sobrescriben. Los hallazgos referidos a esas áreas deben revisarse contra el estado local actual y no contra una base limpia.

Se confirmó un P1 en el aislamiento de autenticación al cambiar entre servidores guardados y doce P2. BUG-014 también está confirmado por inspección: el error del proveedor se convierte en una lista vacía; falta ejecutar la prueba controlada de fallo. El informe previo `Docs/bugs/2026-09-25-investigation.md` conserva investigaciones históricas de PiP y progreso; sus estados se cotejan con el código actual antes de contarlos como regresiones vigentes.

Se confirmaron e implementaron BUG-003, BUG-004, BUG-005, BUG-007, BUG-008, BUG-010, BUG-011 y BUG-016. BUG-006, BUG-012, BUG-013 y BUG-014 siguen pendientes de corrección; BUG-014 está confirmado por inspección. El riesgo histórico BUG-001 parece corregido en los cambios locales actuales mediante la cadena de informes serializada; una prueba nueva comprueba progreso→parada. Esos cambios siguen sin commit y no se han modificado aquí.

## Inventario de incidencias

### BUG-003 — La búsqueda presenta fallos de red como “sin resultados”

- **Prioridad:** P2 — Medio.
- **Categoría:** Estados de error / búsqueda / UX.
- **Archivos implicados:** `Sources/ThisJellyFixFeature/SearchView.swift`, propiedad `body`, `onChange(of: query)`.
- **Evidencia:** líneas 171–188 gestionan el error de `libraryClient.searchItems` con `catch`, vacían `results` y no guardan ningún error. Las líneas 68–78 muestran “Sin resultados para…” cuando ambos arrays están vacíos, sin distinguir error HTTP, desconexión o cero coincidencias.
- **Reproducción:** con sesión iniciada, escribir una consulta de al menos dos caracteres y hacer que el servidor no responda o devuelva un error. La vista termina mostrando el estado de cero resultados.
- **Actual / esperado:** actual: el fallo se representa como búsqueda correcta sin coincidencias; esperado: estado de error con opción de reintentar, manteniendo distinto el caso de respuesta vacía válida.
- **Causa y certeza:** causa confirmada por inspección; no requiere hipótesis.
- **Solución aplicada:** estado de error diferenciado, mensaje de conexión y acción de reintento.
- **Riesgo / pruebas:** bajo. Probar respuesta vacía 200, error de transporte, HTTP no exitoso, cambio de consulta durante una petición y reintento. Pendiente prueba específica de la vista.
- **Impacto esperado:** evita que el usuario concluya que el contenido no está en su biblioteca cuando el servicio está temporalmente inaccesible.
- **Estado:** corregido; iOS y macOS compilan. La vista no tiene test de UI.

### BUG-010 — El indicador de búsqueda puede quedarse girando tras acortar la consulta

- **Prioridad:** P2 — Medio.
- **Categoría:** Estados de carga / búsqueda.
- **Archivos implicados:** `Sources/ThisJellyFixFeature/SearchView.swift`, `onChange(of: query)`.
- **Evidencia:** al cambiar la consulta a menos de dos caracteres se cancela la tarea activa y se sale por el guard antes de limpiar `isSearching`; si la petición ya había iniciado, su tarea cancelada sale por el guard antes de restablecer el estado. La vista podía dejar el spinner activo aunque no hubiera consulta elegible.
- **Reproducción:** introducir una consulta de al menos dos caracteres, esperar a que aparezca el spinner durante la solicitud y borrar hasta un carácter.
- **Actual / esperado:** actual: el estado de carga podía permanecer activo tras cancelar; esperado: volver de inmediato al estado de entrada vacío y cancelar también el indicador del catálogo.
- **Causa y certeza:** confirmada por inspección del orden de cancelación, guard y asignación.
- **Solución aplicada:** al salir del rango mínimo se limpian ambos indicadores de carga junto con los resultados.
- **Riesgo / pruebas:** bajo. Falta una prueba específica de cancelación durante una petición pendiente; se debe compilar búsqueda en todas las plataformas pertinentes.
- **Impacto esperado:** búsqueda predecible al editar o borrar rápidamente.
- **Estado:** corregido; iOS y macOS compilan. Falta test específico de cancelación en curso.

### BUG-011 — Una búsqueda nueva puede mostrar resultados de la consulta anterior

- **Prioridad:** P2 — Medio.
- **Categoría:** Búsqueda / estado asíncrono / feedback.
- **Archivos implicados:** `Sources/ThisJellyFixFeature/SearchView.swift`, `beginSearch(_:)`; `Sources/ThisJellyFixFeature/DiscoveryModel.swift`, `searchCatalog(query:)`.
- **Evidencia:** antes del cambio, `beginSearch` cancelaba la tarea anterior pero no vaciaba `results` ni `catalogResults`; conservaba ambos arrays durante el debounce y la nueva petición. Además, al cancelar una petición de catálogo anterior, la rama de cancelación asignaba `isSearchingCatalog = false`, aunque ya hubiera empezado el catálogo de la consulta nueva.
- **Reproducción:** con catálogo externo configurado y una respuesta lenta, buscar “Alien”, empezar “Aliens” mientras el catálogo de “Alien” sigue en curso; podían verse tarjetas antiguas o desaparecer el indicador de la búsqueda nueva.
- **Actual / esperado:** las tarjetas correspondían temporalmente a una consulta distinta de la que muestra el campo y el spinner podía ocultarse antes de completar la consulta actual; esperado: limpiar resultados al iniciar una consulta nueva y que tareas obsoletas no modifiquen su estado.
- **Causa y certeza:** confirmada por inspección del orden de cancelación/publicación y escrituras compartidas del indicador.
- **Solución aplicada:** `beginSearch` ahora limpia resultados/error y arranca el indicador antes del debounce; una tarea cancelada no apaga el indicador de catálogo de otra consulta.
- **Riesgo / pruebas:** bajo. Falta una prueba automatizada de dos respuestas suspendidas en orden inverso; iOS y macOS compilaron después del cambio.
- **Impacto esperado:** evita que el usuario abra accidentalmente el contenido equivocado y mantiene un estado de carga fiel a la consulta activa.
- **Estado:** corregido; iOS y macOS compilaron después del cambio.

### BUG-004 — Los estantes conservan elementos tras una respuesta vacía válida

- **Prioridad:** P2 — Medio.
- **Categoría:** Frescura de biblioteca / estados inconsistentes.
- **Archivos implicados:** `Sources/ThisJellyFixFeature/LibraryModel.swift`, `loadRow(_:_:)` y `publish(_:)`.
- **Evidencia:** `loadRow` invoca `publish` también cuando el servidor responde correctamente con `[]`; `publish` hacía `guard !row.items.isEmpty else { return }` antes de retirar el valor anterior. Por ello, el refresh exitoso vacío dejaba en pantalla la fila de la carga previa.
- **Reproducción:** cargar una biblioteca con elementos en “Últimos agregados”, retirar esos elementos del conjunto que devuelve el servidor y recargar. Las filas de datos todavía presentes se actualizaban, pero la fila vacía seguía conservando su snapshot anterior.
- **Actual / esperado:** actual: respuesta vacía no reemplaza ni elimina el contenido anterior; esperado: respuesta vacía válida elimina la fila obsoleta. Los errores de red deben conservar el dato anterior, porque en ese caso `publish` no se llama.
- **Causa y certeza:** causa confirmada directamente en el orden de las instrucciones.
- **Solución aplicada:** `publish` ahora retira el snapshot previo y solo añade una nueva fila si tiene contenido.
- **Riesgo / pruebas:** bajo. Prueba de regresión añadida en `LibraryModelCategoryTests`, que carga contenido, cambia la respuesta a vacía y comprueba que la fila desaparezca. La prueba focalizada y la suite completa pasaron.
- **Impacto esperado:** las eliminaciones, elementos reproducidos o cambios de biblioteca reflejan el estado real tras una carga correcta.

### BUG-005 — La cancelación de una descarga borra el estado local aunque falle el servicio

- **Prioridad:** P2 — Medio.
- **Categoría:** Integración *arr / feedback / persistencia de acciones.
- **Archivos implicados:** `Sources/ThisJellyFixDiscovery/DownloadCoordinator.swift`, `removeEntries(matching:)` (líneas aproximadas 242–258); `Sources/ThisJellyFixFeature/DownloadsView.swift`, acciones “Quitar” y “Descartar”.
- **Evidencia:** la eliminación remota usa `try?` y el resultado se ignora; después el coordinador quita todas las coincidencias locales, persiste y refresca. Si la llamada DELETE falla, la fila puede desaparecer temporalmente mientras la orden siga en Radarr/Sonarr. El UI no recibe error de cancelación y el banner existente solo refleja `lastRefreshError`.
- **Reproducción:** intentar quitar una orden mientras el servicio está inaccesible o devuelve HTTP no exitoso; observar que el elemento se elimina de la lista local sin mensaje de fallo.
- **Actual / esperado:** actual: el clic aparenta cancelar aunque el servidor no haya confirmado la cancelación; esperado: conservar/recuperar la entrada y mostrar el rechazo/error.
- **Causa y certeza:** confirmada en el manejo explícito del error; la visibilidad final depende del siguiente refresh exitoso.
- **Solución aplicada:** eliminar localmente solo las entradas con DELETE remoto confirmado; conservar las que fallan, guardar el error de cancelación separado del error de refresh y exponerlo al banner de descargas. También se informa si falta el identificador remoto.
- **Riesgo / pruebas:** bajo-medio. `DownloadCoordinatorTests` cubre el rechazo remoto y caminos de éxito para Radarr/Sonarr; los 25 tests focalizados y la suite completa pasaron. Timeout y fallo parcial necesitan más cobertura.
- **Impacto esperado:** una acción destructiva comunica su resultado correctamente y la lista no miente sobre el estado del servicio.
- **Estado:** corregido; 25 pruebas focalizadas y 278 pruebas totales sin fallos.

### BUG-006 — La carga de segmentos puede solaparse y agotar reintentos por frecuencia del timer

- **Prioridad:** P2 — Medio.
- **Categoría:** Concurrencia / red / saltos de créditos.
- **Archivos implicados:** `Sources/ThisJellyFixFeature/PlayerViewModel.swift`, `loadSegmentsIfNeeded()` y el tick periódico que la invoca.
- **Evidencia:** el tick se ejecuta cada 0,5 s (comentario y configuración en `startUpdating`) y llama `loadSegmentsIfNeeded`; la función solo comprueba `segmentsLoaded`, incrementa `segmentsLoadAttempts` justo antes del `await` y no marca una petición en curso. Si el endpoint tarda más de 0,5 s, ticks posteriores pueden iniciar nuevas llamadas; al tercer tick `segmentsLoadAttempts >= 3` tras un error marca `segmentsLoaded = true` aunque las solicitudes anteriores sigan activas. También publica `segmentMarkers` sin verificar que la respuesta pertenezca todavía al mismo elemento.
- **Reproducción:** con una respuesta de `fetchSegments` retenida más de 1,5 s, permitir que corran ticks; observar múltiples solicitudes. Para verificar publicación obsoleta, cambiar de episodio antes de liberar una respuesta anterior.
- **Actual / esperado:** actual: solicitudes redundantes pueden contar como intentos, detener nuevos intentos prematuramente o publicar marcadores viejos; esperado: máximo una solicitud por elemento, reintentos solo ante fallo terminado y descarte de respuesta si cambió el elemento/sesión.
- **Causa y certeza:** falta de exclusión y de identidad de solicitud confirmada por inspección; el comportamiento bajo latencia necesita prueba dinámica.
- **Solución propuesta:** latch `inFlight` por generación de reproducción, separar contador de fallos terminados del número de ticks, e invalidar respuesta al cambiar elemento o cerrar reproductor.
- **Riesgo / pruebas:** bajo/medio. Pruebas con respuesta controlada retenida, error repetido, cambio de episodio y teardown. `PlayerViewModel.swift` está modificado localmente, así que no apliqué el cambio para evitar interferir con el trabajo en curso.
- **Impacto esperado:** menos tráfico, menos falsos agotamientos de reintentos y ausencia de controles de salto pertenecientes a otro episodio.
- **Estado:** pendiente.

### BUG-007 — Un error al cargar Favoritos se presenta como una lista vacía

- **Prioridad:** P2 — Medio.
- **Categoría:** Estados de error / biblioteca.
- **Archivos implicados:** `Sources/ThisJellyFixFeature/FavoritesView.swift`, `loadFavorites()` y `body`.
- **Evidencia:** `loadFavorites` captura cualquier fallo de ambas solicitudes de favoritos y no actualiza error alguno (`catch` vacío). Al terminar `isLoading`, el `body` ve ambos arrays vacíos y renderiza “Sin favoritos aún”.
- **Reproducción:** abrir Favoritos mientras Jellyfin está inaccesible o una petición devuelve error.
- **Actual / esperado:** actual: error indistinguible de cero favoritos; esperado: estado de error con reintento y conservación de datos previos si existían.
- **Causa y certeza:** confirmada por inspección; el catch no conserva ni comunica el error.
- **Solución aplicada:** se separó error de lista vacía, se añadió mensaje con reintento y se mantienen visibles los datos ya cargados si falla un refresh.
- **Riesgo / pruebas:** bajo. Probar cero resultados 200, error inicial y fallo de refresh con datos previos.
- **Impacto esperado:** evita confundir falta de conexión con pérdida de favoritos.
- **Estado:** corregido; iOS y macOS compilan. La vista no tiene test automatizado de estado de error.

### BUG-008 — Un error de paginación en “Ver todo” se interpreta como fin de la biblioteca

- **Prioridad:** P2 — Medio.
- **Categoría:** Búsqueda/navegación / errores / paginación.
- **Archivos implicados:** `Sources/ThisJellyFixFeature/LibraryModel.swift`, `fetchPage`; `Sources/ThisJellyFixFeature/LibraryGridView.swift`, `loadNextPage()`.
- **Evidencia:** `fetchPage` convierte errores de red/API en `[]`; `loadNextPage` interpreta una página menor a `pageSize` como fin (`hasMore = page.count == pageSize`) y avanza el cursor por el conteo devuelto. El error oculta elementos de la biblioteca y el grid aparenta haber llegado al final.
- **Reproducción:** desplazar un grid paginado hasta pedir una página adicional y provocar un error del servidor.
- **Actual / esperado:** actual: no aparece error/reintento y la paginación termina; esperado: distinguir fallo de respuesta vacía y conservar el cursor para reintentar.
- **Causa y certeza:** confirmada por la conversión a lista vacía y el contrato del consumidor.
- **Solución aplicada:** `fetchPage` propaga el error; el grid conserva las páginas ya visibles, muestra un mensaje y permite reintentar sin avanzar el cursor. Las respuestas `[]` exitosas siguen cerrando la paginación.
- **Riesgo / pruebas:** medio. `LibraryModelPaginationTests` pasó 3/3 y se compilaron iOS/macOS; falta prueba automatizada de la vista y de interacción mientras otra página está activa.
- **Impacto esperado:** acceso completo y fiable a bibliotecas grandes con conexión intermitente.
- **Estado:** corregido en el modelo y la vista; validación focalizada 3/3.

### BUG-012 — “Siguiente episodio” desaparece al final de cada temporada

- **Prioridad:** P2 — Medio.
- **Categoría:** Reproducción / continuidad de series.
- **Archivos implicados:** `Sources/ThisJellyFixFeature/DetailView.swift`, `nextEpisodeAfter(_:)`; `Sources/ThisJellyFixFeature/DirectPlayer.swift`, `resolveNextEpisode()` y `play(_:)`.
- **Evidencia:** ambos flujos buscan el índice del episodio en la lista `episodes`/`seasonEpisodes` de la temporada actual y fijan `nextEpisode = nil` si es el último elemento. `DirectPlayer.resolveNextEpisode()` vuelve a cargar solo esa misma temporada; no consulta la temporada posterior ni `/Shows/NextUp`.
- **Reproducción:** abrir el último episodio de una temporada que tenga una temporada posterior, reproducirlo hasta créditos o usar el control de siguiente.
- **Actual / esperado:** actual: no se ofrece el siguiente episodio y el autoplay no cruza la frontera de temporada; esperado: continuar con el siguiente episodio elegible de la serie siguiendo el orden del servidor.
- **Causa y certeza:** confirmada por la búsqueda limitada a una temporada; probar especiales y temporadas vacías antes de escoger el algoritmo final.
- **Solución propuesta:** resolver sucesor con orden de temporadas/episodios del servidor o usar NextUp cuando su semántica coincida con reproducción manual; mantener el comportamiento de “anterior” y de episodios especiales.
- **Riesgo / pruebas:** medio. Casos: última de temporada, temporadas vacías, especiales, temporada final y serie sin siguiente episodio; se requiere servidor Jellyfin de prueba para confirmar orden.
- **Impacto esperado:** elimina una interrupción frecuente de la reproducción continua de series.
- **Estado:** pendiente.

### BUG-013 — Los errores parciales de Home quedan ocultos tras conservar filas antiguas

- **Prioridad:** P2 — Medio.
- **Categoría:** Biblioteca / sincronización / feedback de red.
- **Archivos implicados:** `Sources/ThisJellyFixFeature/LibraryModel.swift`, `loadRow(_:_:)`, `noteFetchFailure(_:context:surfaceMessage:)`; `Sources/ThisJellyFixFeature/HomeView.swift`, `scrollContent`.
- **Evidencia:** las filas secundarias llaman `noteFetchFailure(..., surfaceMessage: false)` y el `catch` no modifica ni reemplaza la fila previa; Home solo presenta el error global si `rows.isEmpty`. Además, si `fetchViews` falla, se omiten las filas filtradas Películas/Series y categorías, pero otras filas pueden cargar y ocultar el mensaje global. Si una fila falla mientras otras cargan correctamente, el usuario ve una mezcla de datos frescos y una fila anterior, sin indicador por fila ni aviso de actualización parcial.
- **Reproducción:** cargar Home correctamente; después hacer que solo falle el endpoint de una fila (por ejemplo “Últimos agregados”) durante una recarga.
- **Actual / esperado:** actual: el snapshot anterior se mantiene sin explicar que no se pudo actualizar; esperado: conservar el contenido útil y marcar esa fila como desactualizada/con error con opción de reintento.
- **Causa y certeza:** comportamiento confirmado por los `catch` y el estado que consume la vista; la frecuencia depende de fallos parciales de red.
- **Solución propuesta:** representar estado de carga/error/última actualización por fila, sin borrar el último contenido válido.
- **Riesgo / pruebas:** bajo-medio; requiere estado de fila y pruebas de refresh parcial, fallo inicial por fila y reintento.
- **Impacto esperado:** evita presentar silenciosamente información antigua como actual.
- **Estado:** pendiente.

### BUG-014 — Un fallo del catálogo externo puede parecer “sin resultados”

- **Prioridad:** P2 — Medio.
- **Categoría:** Búsqueda / estados de error / descubrimiento externo.
- **Archivos implicados:** `Sources/ThisJellyFixFeature/DiscoveryModel.swift`, `searchCatalog(query:)`; `Sources/ThisJellyFixDiscovery/DiscoveryLoader.swift`, `search(query:library:)`; `Sources/ThisJellyFixFeature/SearchView.swift`, estados vacíos.
- **Evidencia:** `DiscoveryModel.searchCatalog` transforma cualquier error del proveedor en `[]` mediante `try?`. Si la búsqueda Jellyfin también devuelve cero elementos, `SearchView` muestra el mismo estado “Sin resultados” que una búsqueda válida sin coincidencias.
- **Reproducción:** configurar TMDB, dejar sin coincidencias Jellyfin y hacer que el proveedor externo devuelva error o timeout.
- **Actual / esperado:** el fallo del servicio externo se presenta como resultado vacío; esperado: distinguir catálogo no disponible de cero resultados Jellyfin, sin bloquear la mitad local de la búsqueda.
- **Causa y certeza:** confirmada por inspección: `try?` descarta el error y devuelve `[]`; falta una prueba controlada para verificar el estado final de la vista.
- **Solución propuesta:** devolver resultado tipado/estado de error para el catálogo y mostrar feedback secundario con reintento.
- **Riesgo / pruebas:** bajo-medio; pruebas de catálogo con cero resultados, fallo y Jellyfin con resultados independientes.
- **Impacto esperado:** el usuario entiende por qué no aparece contenido externo y evita atribuir al catálogo la ausencia de coincidencias.
- **Estado:** confirmado; pendiente de corrección. Prioridad P2 razonable porque el catálogo es una función opcional y la búsqueda Jellyfin sigue siendo independiente.

### BUG-015 — Dos tamaños de icono no coinciden con sus slots del catálogo

- **Prioridad:** P3 — Bajo.
- **Categoría:** Recursos / calidad de entrega visual.
- **Archivos implicados:** `Apps/iOS/Assets.xcassets/AppIcon.appiconset/Contents.json` y las imágenes `icon_20x20.png`, `icon_20x20@2x.png`, `icon_83.5x83.5@2x.png`.
- **Evidencia:** el catálogo asigna `icon_20x20.png` a un slot de iPhone de 20 pt a 2x (debería medir 40×40), pero el archivo mide 20×20; existe `icon_20x20@2x.png` de 40×40 sin asignar. El slot iPad de 83.5 pt a 2x apunta a un archivo de 83×83 en vez de 167×167. Xcode avisa de ambos tamaños al compilar iOS.
- **Reproducción:** compilar `thisjellyfix-iOS` y revisar los warnings del asset catalog.
- **Actual / esperado:** los slots heredados pueden quedar descartados o reescalados en algunos contextos de icono; esperado: cada slot referencia un recurso con dimensión correspondiente.
- **Causa y certeza:** confirmada por `Contents.json`, `sips` y warnings de `actool`; el impacto visual exacto depende del contexto donde iOS use esos slots.
- **Solución propuesta:** apuntar el slot iPhone 20 pt/2x al recurso existente 40×40 y generar el slot iPad 167×167 desde el master aprobado, sin alterar el arte.
- **Riesgo / pruebas:** bajo. Validar catálogo con `actool` y revisar iconos en iPhone/iPad; no regenerar arte de marca sin aprobación visual.
- **Impacto esperado:** iconos coherentes y sin recursos subdimensionados en dispositivos/contextos heredados.
- **Estado:** pendiente; prioridad baja.

### BUG-016 — Una respuesta de imagen antigua puede reemplazar el arte actual

- **Prioridad:** P2 — Medio.
- **Categoría:** Imágenes / estado asíncrono / identidad de contenido.
- **Archivos implicados:** `Sources/ThisJellyFixFeature/ImageView.swift`, `CachedImageLoader.load(url:fallback:)`, `retryWithFallback(url:)` y `.task(id: url)`.
- **Evidencia:** cuando la URL nueva estaba en caché, `load` asignaba la imagen pero no actualizaba `currentURL`; una descarga anterior seguía satisfaciendo `currentURL == url` y podía sobrescribir el arte nuevo al completarse. Además, el `.task(id:)` no hacía nada si la nueva URL era `nil`, dejando visible la imagen del contenido anterior.
- **Reproducción:** mantener la misma tarjeta SwiftUI (mismo id de elemento), cambiar su URL de arte mientras una descarga está pendiente hacia una URL ya cacheada; alternativamente, quitar el tag de imagen para que el URL nuevo sea `nil`.
- **Actual / esperado:** actual: arte viejo podría terminar en una tarjeta distinta o persistir al desaparecer el URL; esperado: solo la URL vigente puede publicar imagen y `nil` debe mostrar placeholder.
- **Causa y certeza:** confirmada por las guards de publicación y el camino de caché/nil; la frecuencia depende de reutilización de identidad y latencia.
- **Solución aplicada:** el cargador acepta URL opcional, limpia estado ante `nil` y actualiza la identidad vigente antes de servir una imagen cacheada.
- **Riesgo / pruebas:** bajo. iOS y macOS compilaron tras el cambio; falta una prueba de UI con una respuesta suspendida y luego un cambio a URL cacheada/nil.
- **Impacto esperado:** evita portadas incorrectas o arrastradas entre elementos cuando SwiftUI conserva una tarjeta durante una actualización.
- **Estado:** corregido; iOS y macOS compilaron después del cambio.

### BUG-009 — Las credenciales de sesión no están asociadas al servidor seleccionado

- **Prioridad:** P1 — Alto.
- **Categoría:** Autenticación / cambio de servidor / aislamiento de datos.
- **Archivos implicados:** `Sources/ThisJellyFixFeature/AuthModel.swift`, inicialización y `logout()`; `Sources/ThisJellyFixFeature/RootView.swift`, `ServerConnectionModel.select(_:)` y render raíz.
- **Evidencia:** `AuthModel.init` carga un único token, userId y nombre desde claves globales de Keychain, sin guardar el servidor al que pertenecen. La interfaz muestra lista de servidores guardados (`RootView.swift`, vista de conexión), y `select(_:)` cambia `server` y `serverURL`, pero no limpia ni recarga identidad/sesión. `disconnect()` solo limpia la selección URL. No hay `onChange` de servidor que invalide/recree `libraryModel`; solo las rutas de logout lo ponen a nil. Por tanto la raíz puede conservar el `LibraryModel` construido para A y pasarlo junto con el URL/token actuales.
- **Reproducción:** iniciar sesión en Servidor A; desconectar desde la conexión y elegir Servidor B guardado. El estado de autenticación y el `libraryModel` anterior sobreviven; la vista puede seguir usando biblioteca de A mientras muestra/controla el contexto de B. La sesión global puede también enviar el token A a B.
- **Actual / esperado:** actual: sesión y snapshot de biblioteca pueden atravesar el cambio de servidor; esperado: token y datos ligados a un servidor, con invalidación/carga explícita al cambiar y sesión del destino o formulario de login.
- **Causa y certeza:** confirmada por la combinación de almacenamiento no scoped y selector que solo cambia URL; efecto exacto depende de configuración/servidor.
- **Solución propuesta:** introducir sesiones por clave canónica de servidor (manteniendo migración de las claves globales como sesión legacy para el servidor coincidente); al seleccionar, invalidar el modelo de biblioteca anterior y resolver la sesión del destino antes de mostrar contenido. No borrar credenciales de otros servidores al cerrar sesión en uno.
- **Riesgo / pruebas:** alto por migración y datos existentes. El plan por etapas está en `Docs/plans/2026-10-23-auth-server-session-isolation.md`. Probar dos servidores con diferentes usuarios, cambio A→B→A, login parcial, desconexión, logout por servidor y migración desde instalación actual.
- **Impacto esperado:** evita el fallo de acceso y el cruce de identidades entre servidores, un flujo central dado que la app soporta varios servidores guardados.
- **Estado:** pendiente; requiere plan de implementación/migración antes de tocar autenticación.

## Riesgos en investigación

### RISK-001 — Orden de informes de reproducción necesita confirmación con Jellyfin real

Los cambios locales actuales serializan los informes mediante `reportingChain`; `PlayerViewModelCompletionTests.testStopIsSerialisedAfterAnInFlightProgressReport` pasa y verifica el orden progreso→parada con un reporter controlado. La carrera histórica parece corregida a nivel de cliente. Falta comprobar la semántica con Jellyfin real, timeouts/cancelación en segundo plano y cambio de episodio con una petición en curso; no se cuenta como bug confirmado vigente.

### RISK-003 — Aislamiento de concurrencia de delegates y almacenamiento de preferencias

La compilación SwiftPM produjo warnings de `Sendable` para `IntegrationConfig` y `SubtitleProviderStore`, que guardan `UserDefaults` en structs conformes a `Sendable`. La compilación iOS también advirtió que la conformidad de `PipCoordinator` a `AVPictureInPictureControllerDelegate` cruza requisitos no aislados con métodos main-actor; Swift 6 lo elevará a error según el diagnóstico del compilador. Son riesgos reales de migración y merecen resolver explícitamente la frontera de actor, pero las advertencias actuales no prueban por sí solas una carrera observable en Swift 5.10. Validar la cola de callbacks que entrega AVKit antes de elegir aislamiento o `@preconcurrency`.

### RISK-004 — Dos refresh forzados pueden publicar datos de progreso fuera de orden

`LibraryModel.refreshResume(force:)` excluye una segunda solicitud solo cuando `force == false`; las llamadas forzadas pasan mientras otra petición sigue activa. Cada respuesta escribe la misma fila sin comparar generación ni antigüedad. Hay varias rutas de cierre de reproductor que programan `force: true`, y las transiciones de pestaña/escena pueden solicitar un refresh ordinario en paralelo. Si la respuesta de una lectura más antigua llega al final, puede reemplazar la fila actual por un snapshot previo. Además, el primer `defer` pone `isRefreshingResume = false` aunque una segunda petición siga pendiente. No se comprobó una reproducción en runtime; añadir una prueba con dos respuestas retenidas y liberadas en orden inverso antes de clasificarlo como regresión confirmada.

## Cobertura y estado de validación

- **Estructura y límites de módulos:** revisados de forma inicial; SwiftPM separa Core, Networking, Discovery, Playback y Feature. El target Cast solo está en el proyecto Xcode, conforme a las instrucciones del repo.
- **Navegación y autenticación:** inspección parcial de `RootView` y `AuthModel`; la sesión se restaura desde Keychain y valida token de forma asíncrona en `restoreSession` cuando es llamada. Falta verificar sus flujos y plataformas.
- **Cambio entre servidores:** BUG-009 confirmado por inspección; sesiones no están aisladas por servidor.
- **Búsqueda:** BUG-003/010/011 confirmados y corregidos; BUG-014 confirmado por inspección y pendiente de corrección.
- **Vaciamiento de filas al refrescar:** corregido y con prueba de regresión añadida (BUG-004).
- **Descargas:** BUG-005 corregido; un DELETE fallido conserva la entrada y su error llega al banner.
- **Segmentos:** el solapamiento histórico sigue presente y se registra como BUG-006 confirmado por inspección.
- **Favoritos:** el error se diferencia del estado vacío; se conserva la lista previa y se ofrece reintento (BUG-007 corregido).
- **Grids paginados:** BUG-008 corregido; se preserva la lista y aparece opción de reintento ante error.
- **Carga de imágenes:** BUG-016 corregido; las respuestas antiguas no deben sobrescribir el arte cacheado vigente y URL nula limpia la imagen.
- **Continuidad entre temporadas:** BUG-012 confirmado por inspección; el reproductor solo conoce episodios de su temporada actual.
- **Errores parciales de Home:** BUG-013 confirmado por inspección; las filas fallidas conservan el snapshot sin feedback por fila.
- **Reproducción, sincronización, PiP, AirPlay y Next Up:** inspección estática parcial; falta prueba dinámica, y parte está afectada por cambios locales.
- **Pruebas:** `swift test` compiló y ejecutó **278 tests, 0 fallos** después de los cambios de búsqueda; `DownloadCoordinatorTests` pasó 25/25 y `LibraryModelPaginationTests` 3/3. El último cambio de imágenes es de UI y quedó compilado con Xcode.
- **Compilaciones Xcode/plataformas:** iOS Simulator y macOS compilaron después del arreglo de imágenes; tvOS/visionOS pasaron antes de los cambios más recientes y no se repitieron. Se observaron warnings de concurrencia `Sendable`/delegate PiP, código sin uso, APIs Cast deprecadas y tamaños de iconos mal configurados.
- **Servidor/dispositivos reales:** no se usaron en esta pasada; no se afirma validación de integración real.

## Recomendación UX/UI inicial

Priorizar estados diferenciados de carga, error, desconexión y cero resultados en las superficies que hoy consumen errores. Búsqueda, favoritos, cancelación y paginación ya separan algunos fallos de sus estados vacíos o de éxito; falta validación manual de las interacciones. No se recomienda un rediseño visual general: la inspección debe determinar primero si hay problemas verificables de jerarquía, legibilidad, accesibilidad o navegación.

### Mejoras de UX/UI priorizadas

1. **Sesión correcta al cambiar de servidor:** aislar identidad y estado por origen Jellyfin (BUG-009). Beneficio: evita que la biblioteca use credenciales de otro servidor.
2. **Catálogo completo en red inestable:** BUG-008 ya conserva cursor y muestra reintento; validar visualmente el mensaje y su recuperación en iOS/macOS.
3. **Confianza en las acciones de descarga:** BUG-005 conserva la entrada y presenta error si falla el DELETE; probar timeout y fallos parciales con un servicio real.
4. **Progreso de reproducción fiable:** la cadena serializada de informes y la finalización al alcanzar el final son cambios locales positivos, sujetos a los tests nuevos; completar la prevención de respuestas obsoletas de segmentos (BUG-006).
5. **Conservar la identidad existente:** MareaTheme y las pruebas de contraste/movimiento muestran una base de diseño intencional; no se recomienda sustituirla. Falta validar visualmente en dispositivos las proporciones de portada, legibilidad en tamaños grandes, foco de tvOS, VoiceOver y transiciones.

La evaluación visual y de interacción queda parcialmente limitada: no se ejecutó manualmente la app en un simulador o dispositivo con servidor/media real. Los builds demuestran compilación de ramas, no calidad de reproducción ni percepción visual.

## Próximos pasos

1. Ejecutar el plan existente de migración de sesiones BUG-009; preservar y verificar tokens guardados antes de cambiar el esquema.
2. Validar el error y reintento de paginación BUG-008 en la vista y en iOS/macOS.
3. Corregir la coordinación de segmentos BUG-006 con respuestas suspendidas y cambio de episodio.
4. Auditar en profundidad las interrupciones reales, recuperación PiP/AirPlay, cambio de pistas, sesión de usuario y eventos de cierre; usar Jellyfin de prueba y dispositivos/simuladores funcionales.
5. Hacer pasada visual/accesibilidad con VoiceOver, Dynamic Type, reducción de movimiento y foco tvOS; sumar evidencia/fotos por plataforma.

## Estado integral y límites

Esta versión del informe reúne la primera ronda verificable de la auditoría, no cierra todo el encargo. Los flujos funcionales del reproductor, autenticación expirada, estado entre usuarios/servidores, transiciones PiP/AirPlay, interrupciones, TV focus y métricas de rendimiento requieren pruebas dinámicas con hardware/servidor. Hasta esa fase, no se declara ausencia de fallos en esos flujos. El análisis estático sí cubrió estructura, clientes de red, búsqueda, biblioteca, descargas, favoritos, paginación y partes del ciclo de reportes.


### Registro de esta continuación — 2026-10-23

- Se corrigió la clasificación de BUG-014: `DiscoveryModel.searchCatalog` descarta los errores con `try?`, por lo que el fallo se representa como `[]`; el caso está confirmado por inspección y falta la prueba controlada del proveedor.
- Se armonizó el resumen: 1 P1 y 12 P2 confirmados; BUG-003/004/005/007/008/010/011/016 implementados, BUG-006/012/013/014 pendientes de corrección.
- Revalidación de tests intentada en este entorno: bloqueada antes de compilar por permisos del sandbox (`sandbox_apply: Operation not permitted` al cargar el manifiesto SwiftPM). El registro previo de 278/278 sigue siendo la última ejecución exitosa documentada.
- `git diff --check` pasó durante esta revisión.

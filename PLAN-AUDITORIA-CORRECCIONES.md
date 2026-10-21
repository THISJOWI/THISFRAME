# Plan de corrección — Auditoría de ThisJellyFix

**Fecha:** 2026-10-20  
**Alcance:** planificación de los riesgos identificados; no incluye cambios de implementación.

## Resumen

La auditoría estática identificó dos riesgos probables, ambos de prioridad media (P2), relacionados con la coordinación de operaciones asíncronas:

| ID | Problema | Área | Prioridad | Confianza |
|---|---|---|---|---|
| BUG-001 | Los informes de progreso y parada pueden llegar a Jellyfin fuera de orden. | Informes de reproducción | P2 | Probable |
| BUG-002 | El temporizador puede iniciar solicitudes concurrentes repetidas para cargar segmentos. | Concurrencia y red | P2 | Probable |

No se identificaron hallazgos P0 o P1 en el análisis realizado. Los comportamientos necesitan validación dinámica con latencia y respuestas controladas.

## BUG-001 — Informes de reproducción fuera de orden

**Evidencia:** `Sources/ThisJellyFixFeature/PlayerViewModel.swift`, métodos `reportProgress(at:)` y `reportStopped()` (aprox. líneas 2219–2271). Cada operación crea una tarea independiente. `Sources/ThisJellyFixNetworking/JellyfinPlaybackClient.swift` contiene el reporter HTTP, sin coordinación visible entre informes.

**Mecanismo:** una petición de progreso puede quedar pendiente mientras se envía y completa un informe de parada o un informe del siguiente episodio. Si las respuestas llegan en otro orden, un estado antiguo podría actualizar Jellyfin después del cierre o cambio.

**Impacto posible:** posición de reanudación o sesión de reproducción incoherentes.

### Solución propuesta

- Coordinar los informes por sesión y elemento, conservando el orden lógico de inicio, progreso y parada.
- Invalidar o descartar informes que pertenezcan a un elemento anterior tras un cambio de episodio.
- Mantener la interfaz independiente de la latencia de los informes y definir el comportamiento ante errores o timeout.
- Evitar duplicar la política de orden en distintos llamadores; establecer un único punto responsable en el reporter o en una capa de sesión claramente definida.

### Criterios de aceptación

- Un progreso antiguo no actualiza el estado después de la parada de esa sesión.
- Un informe del elemento anterior no afecta al episodio nuevo.
- Un fallo o timeout de red no bloquea la reproducción ni impide iniciar otra sesión.
- Los informes periódicos siguen enviando la posición correcta y se conserva la protección existente contra informes de posición cero.

### Pruebas necesarias

1. Simular progreso lento y parada rápida; comprobar el orden observado por el servidor de prueba.
2. Cambiar de episodio mientras hay un progreso pendiente; confirmar que no se atribuye al nuevo elemento ni llega después de su estado final.
3. Repetir salida normal, cierre durante buffering y cierre en PiP.
4. Simular timeout y error del servidor; comprobar que la UI sigue respondiendo y los informes posteriores pueden continuar.

## BUG-002 — Solicitudes concurrentes de segmentos

**Evidencia:** `Sources/ThisJellyFixFeature/PlayerViewModel.swift`, el temporizador periódico crea tareas cada 0,5 segundos (aprox. línea 1215); el tick llama a `loadSegmentsIfNeeded()` (aprox. línea 1315). El método inicia una petición antes de marcar la carga como completada y no tiene una marca explícita de solicitud en curso (aprox. líneas 1340–1358).

**Mecanismo:** si una solicitud tarda más que un tick, nuevos ticks pueden iniciar otras solicitudes. El contador de intentos puede alcanzar el límite mientras solicitudes anteriores siguen pendientes. Una respuesta tardía puede modificar el estado tras ese límite.

**Impacto posible:** tráfico redundante, reintentos agotados prematuramente y resultados dependientes del orden de respuesta.

### Solución propuesta

- Mantener una sola solicitud de segmentos en curso por elemento.
- Hacer que los ticks posteriores no inicien otra solicitud mientras la carga siga activa.
- Asociar el resultado a la generación/identidad del elemento y descartar respuestas obsoletas tras un cambio de episodio o teardown.
- Definir explícitamente el número y momento de reintentos ante error transitorio; no contar como intentos concurrentes las comprobaciones del temporizador.

### Criterios de aceptación

- Nunca hay más de una petición de segmentos activa para el mismo elemento.
- Los ticks periódicos no multiplican las llamadas durante una petición lenta.
- Las respuestas de un episodio anterior no modifican los marcadores del episodio actual.
- Los reintentos ante error respetan el límite definido y una petición lenta no consume varios intentos por sí sola.

### Pruebas necesarias

1. Mantener una respuesta pendiente durante varios ticks y comprobar que solo se inicia una petición.
2. Completar la primera petición con éxito y verificar que los marcadores aparecen una sola vez.
3. Fallar la petición y comprobar el número y espaciado de reintentos.
4. Cambiar de episodio mientras la petición está pendiente y comprobar que su respuesta se descarta.
5. Cerrar el reproductor durante la carga y comprobar que no se actualiza estado inactivo.

## Orden de ejecución

### Fase 1 — Pruebas de caracterización

Añadir pruebas con clientes de red simulados que permitan retener y completar respuestas en orden arbitrario. Establecer primero el comportamiento esperado para ambos riesgos.

**Cubre:** BUG-001 y BUG-002.  
**Dependencias:** ninguna.  
**Aceptación:** las pruebas reproducen el riesgo bajo la secuencia de latencias indicada, antes de aplicar la solución.

### Fase 2 — Serialización e invalidación de informes

Implementar la coordinación por sesión/elemento y descartar informes obsoletos. Ejecutar las pruebas de caracterización, además de regresiones de pausa, cierre, PiP, cambio de episodio y progreso de reanudación.

**Cubre:** BUG-001.  
**Dependencia:** Fase 1.  
**Aceptación:** se satisfacen los criterios de BUG-001 y el flujo normal de informes sigue operativo.

### Fase 3 — Exclusión de cargas simultáneas

Implementar una única carga activa de segmentos por elemento y validar la identidad del elemento al publicar el resultado.

**Cubre:** BUG-002.  
**Dependencia:** Fase 1.  
**Aceptación:** se satisfacen los criterios de BUG-002 y el refresco funciona tras cambios de episodio.

### Fase 4 — Regresión multiplataforma y de flujos

Ejecutar las pruebas aplicables en iOS, macOS, tvOS y visionOS. Probar PiP en iOS; verificar segmentos e informes de reproducción en las demás plataformas compatibles.

**Cubre:** posibles regresiones de las Fases 2 y 3.  
**Dependencias:** Fases 2 y 3.  
**Aceptación:** sin diferencias inesperadas en reproducción, progreso, cambios de episodio, PiP ni estados de error.

## Matriz consolidada de regresión

| Prueba | Preparación y pasos | Resultado esperado | Relación |
|---|---|---|---|
| Reproducción normal | Iniciar un elemento y reproducirlo durante más de un intervalo de informe. | Jellyfin recibe inicio y progreso del elemento y posición correctos. | BUG-001 |
| Cierre y reapertura | Reproducir, cerrar y volver a abrir el mismo elemento. | La parada finaliza la sesión anterior; la posición guardada se reanuda. | BUG-001 |
| Cambio de episodio | Cambiar con un informe de progreso pendiente. | No se aplica progreso obsoleto al elemento nuevo ni después de su parada. | BUG-001 |
| PiP | Activar PiP, volver a pantalla completa y cerrar la ventana. | La sesión conserva su estado durante la transición y termina al cerrarse. | BUG-001 |
| Carga lenta de segmentos | Retener la respuesta más de varios ticks del temporizador. | Solo una solicitud queda activa para el elemento. | BUG-002 |
| Error de segmentos | Fallar la petición y dejar que ocurran los reintentos definidos. | Se respeta el límite; la UI y la reproducción siguen funcionando. | BUG-002 |
| Cambio durante carga | Cambiar episodio antes de recibir los marcadores. | La respuesta anterior no cambia el elemento nuevo. | BUG-002 |
| Cierre durante carga | Cerrar el reproductor con la petición pendiente. | No se publica estado en un reproductor detenido. | BUG-002 |
| Red interrumpida | Simular desconexión, timeout y respuesta 5xx. | No hay bloqueo de UI; las operaciones posteriores siguen funcionando. | Ambos |
| Compatibilidad | Repetir los flujos compatibles por plataforma. | No aparecen regresiones específicas de plataforma. | Ambos |

## Riesgos y validación pendiente

- Los dos hallazgos son probables, no confirmados: dependen de tiempos de red y orden de respuesta que el análisis estático no revela.
- La auditoría no ejecutó compilaciones ni pruebas; todas las comprobaciones de este plan están pendientes.
- Deben comprobarse las interacciones con PiP y Cast en los destinos donde estén disponibles.
- Antes de implementar, confirmar el contrato de estado esperado con Jellyfin cuando llega progreso después de una parada y decidir la política de reintentos para segmentos.

# Auditoría de continuidad y consumo del harness

[← Índice](../README.md) · [Prácticas para LLM](../guides/llm-practices.md)

Revisión del 2026-10-15 sobre `a1ef90d` (`v0.14.1`) y los cambios de trabajo
descritos aquí. El análisis usa código, historial Git y pruebas locales; no se
ha medido el ahorro de cuota con una cuenta de ChatGPT. Los cambios existentes
del usuario en `.gitignore` y la eliminación de `CONTRIBUTING.md` se conservan.

## Qué muestra la evolución

| Etapa | Decisión relevante |
| --- | --- |
| `v0.1.0`–`v0.2.0` | Interfaz Qt, puente con Codex e historial persistente |
| `v0.3.0` | Conexión propia a ChatGPT; contexto reconstruido localmente y `store: false` |
| `v0.4.0` | Métricas para separar tiempos y tokens reportados |
| `v0.7.0` (`d20db37`) | Shell estructurada, persistencia de llamadas/resultados y límite de ocho pasos |
| `v0.9.0` | Ejecución automática y `/shell` local sin inferencia |
| `v0.10.0`–`v0.13.0` | Work, visores, cambios en vivo y consulta de cuota; los visores no alimentan el contexto |
| `v0.14.0` (`620f756`) | Entorno gráfico conservado, esfuerzo configurable e inicio de proyectos reutilizable sin IA |
| `v0.14.1` (`a1ef90d`) | Separación de paquetes, documentos y pruebas; base de 230 pruebas Python |

Las mejoras de interfaz y de inicio ya evitaban inferencia innecesaria. El bucle
conversacional seguía conservando límites de la primera integración de shell.

## Hallazgos corregidos

### Alta: EOF de salida terminaba procesos válidos

`ShellExecutor.execute` esperaba sólo mientras hubiera descriptores en el
selector. Un proceso que cerraba stdout/stderr y seguía trabajando hacía salir
del bucle; el `finally` mataba el grupo. Esto puede ocurrir en programas que
redirigen sus propios logs.

Ahora se espera a la terminación del proceso aunque ya no tenga tuberías
abiertas. Timeout y cancelación siguen activos. Regresiones reales comprueban
un archivo escrito después de cerrar stdout, timeout y cancelación en ese estado.

### Alta: tareas de varios pasos se cortaban por un límite heredado

El bucle permitía ocho solicitudes y rechazaba las herramientas de la octava.
Con una herramienta por solicitud sólo ejecutaba siete. Después pedía otro
mensaje del usuario, incluso si el modelo tenía una siguiente acción concreta.

Ahora el turno permite por defecto 32 solicitudes y 64 herramientas, con límites
configurables. Las herramientas de la última solicitud permitida pueden
ejecutarse y sus resultados se conservan; si falta otra solicitud para concluir,
el estado es `failed` con explicación del límite. Se verifica una tarea de doce
comandos más respuesta final y la conservación de cada resultado al agotar pasos.

No hay un bucle ilimitado. Un tope de recursos y una condición verificable de
terminación cumplen funciones distintas: ampliar el primero no prueba la segunda.

### Alta: un comentario intermedio se confundía con tarea terminada

La ausencia de `function_call` cerraba el turno incluso si todos los mensajes
eran `phase: commentary`. Ahora ese caso añade una instrucción breve de
continuación al contexto y sigue dentro del mismo presupuesto. No añade un
mensaje ficticio del usuario. Una respuesta vacía sin texto ni herramientas
se informa como fallo, y los comentarios repetidos también quedan acotados.

Se conservan mensajes sin `phase` por compatibilidad con proveedores que no la
incluyen. Un mensaje final o sin esa fase explícita aún puede cerrar el turno:
el harness no verifica semánticamente todos los criterios de una tarea.

### Media: el recorte ocultaba el diagnóstico final y reenviaba demasiado texto

El ejecutor conservaba sólo los primeros 16.000 caracteres; cada resultado
entraba completo al contexto y volvía a viajar en solicitudes posteriores.
El error final de compilación o pruebas podía desaparecer.

Ahora la captura de la tarjeta conserva inicio y final hasta 16.000 caracteres.
`compact_result` prepara una vista de hasta 6.000 para el modelo, con estado,
código de salida y aviso de recorte. La duración queda en la tarjeta y en las
métricas. El recorte se aplica al insertar resultados nuevos; no reescribe el
prefijo ya persistido ni elimina razonamiento cifrado o pares de herramientas.
La preparación interna de **Ejecutar** también usa esa vista reducida.

El máximo de texto de salida por resultado baja un 62,5 % (16.000 → 6.000);
eso no equivale a ahorrar un 62,5 % de tokens, de la solicitud completa o de cuota.
Las pruebas verifican el payload enviado, su límite, el error final y la captura
más amplia en el historial visible. El centro descartado no queda archivado
automáticamente: los comandos deben guardar un log si hace falta recuperarlo.

### Media: un `output` final parcial podía perder contexto de razonamiento

El adaptador recuperaba `response.output_item.done` únicamente si el `output`
de `response.completed` estaba vacío. Un resumen con sólo algunas herramientas
podía dejar fuera el razonamiento cifrado u otros mensajes completos del stream.

Ahora combina los elementos completados por índice con los finales por ID,
conserva campos ausentes y rechaza IDs finales duplicados en esa reconstrucción.
Ninguna herramienta se ejecuta antes de `response.completed`. Las regresiones
comprueban el razonamiento, el orden y la unicidad de la llamada.

### Media: conexiones HTTP permanecían abiertas durante shell

El consumidor abandonaba el generador al recibir `response.completed` sin
cerrarlo explícitamente. El socket podía seguir asociado al turno durante la
ejecución local, hasta el reemplazo del iterador o su recolección.

El servidor cierra el stream en `finally` antes de ejecutar herramientas, y el
adaptador propaga el cierre al transporte. Una prueba comprueba que el control
HTTP ya no mantiene una conexión al entrar en el ejecutor.

### Media: reintentos sin progreso y eventos locales redundantes

No había detección de fallos repetidos ni presupuesto opcional de tokens. Ahora
tres fallos consecutivos del mismo comando con el mismo estado, código y salida
detienen el turno. Las diferencias de duración o formato del JSON no reinician
la cuenta; un éxito o evidencia distinta sí. No se bloquean comandos repetidos
que tengan éxito, ya que pueden ser verificaciones legítimas.

El presupuesto opcional usa `usage.total_tokens` recibido y se revisa antes de
la próxima solicitud. No estima consumo desconocido. Los pasos y comandos
mantienen topes independientes del reporte de tokens.

La shell conserva el pulso de 250 ms que necesita la comprobación de inicio de
Work, pero el servidor y `ProjectRunner` evitan publicar estados idénticos.
Esto reduce tráfico NDJSON y escrituras causadas por salida invariable; no
reduce tokens por sí mismo.

## Invariantes que se conservan

- Esquema 1 del historial y NDJSON v2. `shell.state` añade el campo opcional
  `agent_timeout_seconds`; `timeout_seconds` sigue describiendo `/shell`.
- Escritura de la llamada antes de crear el proceso y resultado antes de
  consultar de nuevo al modelo. Recuperar historial no reejecuta comandos.
- `call_id`, fases de mensajes y razonamiento cifrado para continuar Responses.
- `Detener` cancela HTTP y el grupo de procesos; generaciones antiguas no
  modifican turnos posteriores.
- `/shell` sigue sin inferencia y con 120 segundos; los comandos de la IA tienen
  300 segundos por defecto. El programa principal de **Ejecutar** sigue sin timeout.
- Sin nuevas dependencias, cambios de modelos automáticos ni migración destructiva.

## Pendientes y límites reales

| Prioridad | Observación o riesgo | Próximo trabajo y criterio de aceptación |
| --- | --- | --- |
| Alta | El contexto completo sigue creciendo; mensajes, imágenes y razonamiento pueden alcanzar la ventana del modelo | Compactación por bloques completos con checkpoint de objetivo, decisiones, archivos y verificaciones; preservar herramientas pendientes, cancelar de forma segura y medir pérdida de información |
| Alta | Una respuesta final no demuestra que se cumplieron todos los requisitos | Evaluaciones de tareas con resultados comprobables: archivo esperado, pruebas relevantes y errores visibles; evitar continuar a ciegas después de cualquier respuesta final |
| Media | Errores HTTP y streams incompletos interrumpen el turno | Recuperación explícita con backoff acotado y clasificación de fallos; no repetir inferencia ambigua ni efectos de shell; respetar cancelación y límites de cuenta |
| Media | HTTP tiene un timeout de socket de 30 s por defecto | Medir pausas reales del proveedor antes de separar plazo de conexión, lectura e inactividad; no confundir timeout de socket con tiempo máximo de una tarea |
| Media | `HistoryStore.list()` y `performance()` cargan y validan JSON completos, incluidas imágenes | Índice o caché de metadatos con invalidación por cambios de archivo; verificar mejora con muchos chats sin ocultar corrupción |
| Media | El contexto antiguo conserva resultados grandes creados por versiones anteriores | Migración o compactación explícita; evitar recortar cada solicitud y romper el prefijo de forma continua |
| Media | La preparación de **Ejecutar** conserva su límite independiente de ocho solicitudes/comandos | Medir proyectos que no alcanzan a prepararse antes de aumentar ese presupuesto; ya dispone de caché de inicio |
| Baja | No hay PTY, entrada interactiva ni gestor general de trabajos persistentes del agente | Diseñar sesiones y espera con ciclo de vida explícito; comprobar cancelación, salida limitada y limpieza de descendientes |

Las variables de entorno permiten ampliar presupuestos, pero no solucionan una
cuota agotada, dependencias ausentes o decisiones incorrectas del modelo. No se
ha añadido una continuación automática después de errores de red o reinicios.

## Evidencia y reproducción

```sh
./scripts/check.sh
./scripts/smoke.sh
```

Base anterior: 230 pruebas Python. Tras estos cambios: 255 pruebas Python,
revisión QML y 12 escenarios de integración Qt. Las regresiones principales están en
`tests/backend/tools/test_shell.py`, `tests/backend/core/test_harness.py`,
`tests/backend/core/test_limits.py` y `tests/backend/chat/test_stream.py`.
Los escenarios Qt comprueban la integración mediante el backend simulado y
procesos reales. No se usan OAuth ni inferencia de una cuenta real.

Para medir ahorro real, compara tareas equivalentes sobre copias del mismo
estado inicial: resultado correcto, llamadas, entrada acumulada, salida,
razonamiento, caché y tiempo. Registra modelo/esfuerzo, contexto inicial y estado
de caché. El porcentaje del plan no debe deducirse de caracteres ni de tokens
locales. [Cómo interpretar las métricas](../guides/performance.md).

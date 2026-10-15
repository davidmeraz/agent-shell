# Aprovechar los LLM en Agent Shell

[← Índice](../README.md) · [Auditoría del harness](../technical/harness-audit.md)

Esta guía describe el backend Python y la interfaz Qt actuales. El objetivo es
completar tareas con evidencia, reduciendo lecturas, respuestas y llamadas que
no aportan información. Los límites de tokens del harness son controles locales;
no representan el porcentaje disponible de tu plan de ChatGPT.

## Elegir el camino que consume menos inferencia

| Necesidad | Camino en la aplicación |
| --- | --- |
| Ejecutar una orden que ya conoces | `/shell orden`: cero solicitudes al modelo; la salida queda local |
| Arrancar un proyecto que ya tiene inicio guardado | **Ejecutar**: reutiliza el comando si sigue siendo válido |
| Leer un archivo tú mismo | Explorador y visores: no envían el contenido al LLM |
| Diagnosticar, modificar o verificar código | **Work**, con un objetivo y criterios de aceptación concretos |
| Conversar sin trabajar en archivos | **Chat**; el modelo puede responder sin herramientas |

La primera detección de **Ejecutar** sí consume inferencia. También puede
consumirla de nuevo si se invalida el inicio o falla. La consulta de uso del plan
no genera respuestas del modelo. `/shell` no transmite su resultado al LLM:
si necesitas que lo analice, pide a la IA que ejecute la comprobación o proporciona
el fragmento relevante en un mensaje.

## Pedir una tarea completa

Una solicitud útil establece resultado, alcance y comprobación. Ejemplo:

```text
En este proyecto, corrige que el proceso se interrumpa al cerrar stdout.
Primero lee AGENTS.md si existe y localiza el ejecutor y sus pruebas.
Conserva la cancelación y el timeout. Añade una regresión con un proceso que
cierre stdout y siga escribiendo un archivo. Ejecuta las pruebas afectadas
y termina indicando el cambio, la comprobación y cualquier bloqueo real.
Continúa con la implementación y la verificación dentro de esta tarea.
```

Evita encadenar mensajes que sólo digan «continúa»: cada uno añade contexto y
puede provocar otra inspección. Da al agente el objetivo completo desde el
principio. Para tareas grandes, define entregables verificables por etapa.
Un límite local, un error de conexión o una cancelación pueden terminar el turno;
en esos casos los cambios realizados se conservan y el resultado no se marca
como completado por el harness.

El ciclo continúa al recibir herramientas y ante mensajes explícitos con
`phase: commentary`. Una respuesta final sigue siendo una declaración del modelo:
para evaluar si cumplió, revisa los resultados de las comprobaciones acordadas.
El harness no interpreta una frase como «listo» como prueba de corrección.

## Contexto de proyecto pequeño y útil

Mantén un `AGENTS.md` breve por proyecto con información difícil de deducir:

```markdown
# Trabajo en este proyecto
- Backend: backend/harness/. Interfaz: ui/. Pruebas: tests/.
- Ejecutar: ./scripts/run.sh
- Comprobar: ./scripts/check.sh
- Si cambias el protocolo o la UI: ./scripts/smoke.sh
- Usa .venv/bin/python para este repositorio.
- Conserva la compatibilidad NDJSON v2 y el esquema 1 del historial.
- Lee sólo los archivos relevantes; no adjuntes .runtime/, entornos ni dependencias.
```

Este bloque es una plantilla, no una configuración que se haya instalado en el
repositorio. En el chat de Work se instruye al modelo para que inspeccione las
instrucciones locales; no hay un cargador general que inyecte automáticamente
todos los `AGENTS.md`. Pide su lectura al comienzo. La detección interna del botón
**Ejecutar** sí tiene su propia lectura previa acotada.

Usa `rg --files` para localizar rutas y `rg -n 'patrón' ruta` para localizar
símbolos. Lee rangos concretos con `sed -n '80,160p' archivo`. Evita `cat` de todo
el repositorio, búsquedas recursivas sin exclusiones y árboles completos de
dependencias. Lee de nuevo cuando hubo cambios, datos omitidos o una nueva duda.

Conserva una conversación para una tarea relacionada. Al cambiar de objetivo,
prepara un resumen de decisiones, archivos, verificaciones y pendientes y abre
un chat nuevo. El historial completo crece y se vuelve a enviar; no existe aún
compactación automática. Un resumen solicitado al modelo también consume una
llamada y puede perder detalles: comprueba los datos relevantes.

Adjunta imágenes sólo cuando la información visual sea necesaria. Una captura
recortada al problema suele aportar contexto más útil que todo el escritorio.
Las imágenes de mensajes anteriores permanecen en el contexto de esa conversación.

## Trabajar con la shell de este harness

Cada llamada ejecuta `/bin/sh -c` en un proceso nuevo. `cd`, `export` y activar
un entorno sólo afectan esa llamada. Usa rutas explícitas como
`.venv/bin/python`, configura la carpeta con `/terminal` o combina pasos
dependientes con `&&`:

```sh
cd subproyecto && .venv/bin/python -m unittest discover -s tests
```

Agrupa inspecciones pequeñas y relacionadas para ahorrar viajes al modelo.
Separa una comprobación de una modificación cuando debas decidir según su salida.
No presupongas que `comando1; comando2` conserva el error del primero: la salida
de la shell puede ser la del último comando. En `/bin/sh` tampoco debes asumir
que una tubería conserva el fallo de todos sus componentes.

Para logs grandes, conserva un archivo y muestra un fragmento sin perder el
código de salida del proceso. Por ejemplo, en este repositorio:

```sh
./scripts/check.sh > /tmp/agent-shell-check.log 2>&1
check_status=$?
tail -n 60 /tmp/agent-shell-check.log
exit "$check_status"
```

Si falta información, consulta un rango del archivo; no repitas toda la ejecución
sólo para ver otro fragmento. `[…]` indica que se omitió el centro de la salida.
La tarjeta retiene hasta 16.000 caracteres; la entrada nueva del modelo, hasta
6.000 por resultado de shell por defecto. Ambos conservan comienzo y final.
El archivo del ejemplo permite recuperar lo que ninguna de esas vistas conserva.

No hay stdin interactivo ni PTY. Una contraseña de sudo, un editor interactivo
o una confirmación de un instalador pueden bloquear el trabajo. Usa modos no
interactivos apropiados para la tarea y ejecuta personalmente los pasos que
requieren entrada de usuario. Para servidores y programas persistentes usa
**Ejecutar** en Work; los comandos normales tienen timeout y sus descendientes
del mismo grupo se terminan al salir la orden principal.

## Configurar duración y gasto

Las variables se leen al iniciar el backend normal. Cierra Agent Shell antes
de cambiar la configuración: el lanzador evita abrir instancias duplicadas.

| Variable | Predeterminado | Rango y efecto |
| --- | ---: | --- |
| `AGENT_SHELL_MAX_STEPS` | 32 | 1–256 solicitudes al modelo por turno, incluida la respuesta final |
| `AGENT_SHELL_MAX_TOOL_CALLS` | 64 | 1–1024 llamadas de herramienta por turno; cuenta también solicitudes inválidas |
| `AGENT_SHELL_COMMAND_TIMEOUT` | 300 | 1–3600 segundos por comando solicitado por la IA en Chat/Work |
| `AGENT_SHELL_CONTEXT_OUTPUT_CHARS` | 6000 | 256–16000 caracteres de salida por resultado nuevo enviado al modelo conversacional |
| `AGENT_SHELL_MAX_TURN_TOKENS` | 0 | 0 desactiva el límite; 1–100000000 limita la suma de `usage.total_tokens` reportada |
| `AGENT_SHELL_REPEATED_FAILURES` | 3 | 2–20 fallos consecutivos idénticos antes de detener el turno |

Una configuración inválida produce un error al iniciar. El presupuesto de tokens
se comprueba antes de la siguiente solicitud: una respuesta puede superarlo y
los datos ausentes impiden conocer el consumo completo. No es un límite duro de
facturación, ni limita tokens de salida dentro de una solicitud. El límite por
pasos funciona aunque el proveedor no reporte tokens. Llegar a cualquiera de
estos límites conserva el historial y los resultados; no deshace archivos.

Ejemplo para una tarea extensa con comandos de hasta diez minutos:

```sh
AGENT_SHELL_MAX_STEPS=48 \
AGENT_SHELL_MAX_TOOL_CALLS=96 \
AGENT_SHELL_COMMAND_TIMEOUT=600 \
./scripts/run.sh
```

Ejemplo de presupuesto experimental más acotado, que debes ajustar con tus
mediciones y que puede detener una tarea antes de completarla:

```sh
AGENT_SHELL_MAX_STEPS=16 \
AGENT_SHELL_CONTEXT_OUTPUT_CHARS=4000 \
AGENT_SHELL_MAX_TURN_TOKENS=40000 \
./scripts/run.sh
```

`/shell` conserva 120 segundos. El botón **Ejecutar** conserva su presupuesto
independiente de detección/preparación y su proceso principal sin timeout.
Su contexto de preparación usa un recorte fijo de 6.000 caracteres. Las variables
de la tabla no controlan esa tarea interna. Los límites se reinician con cada
mensaje del usuario; no son límites diarios ni por conversación.

## Elegir modelo y esfuerzo con datos

Utiliza `/modelos` y los niveles que anuncie tu cuenta. Como experimento local,
empieza una tarea pequeña con esfuerzo bajo si está disponible y aumenta el
esfuerzo cuando las comprobaciones muestren errores de razonamiento. Para una
depuración difícil puede convenir comenzar con mayor esfuerzo y evitar varios
intentos fallidos. **Auto** usa la decisión del servidor; no significa consumo
mínimo. Estas pautas deben contrastarse en tus proyectos, no garantizan ahorro.

En **Rendimiento**, compara tareas equivalentes por resultado correcto, número
de llamadas, entrada acumulada, salida, razonamiento, caché y duración. El
indicador **Contexto** muestra la entrada de la última llamada; no el gasto de
todo el turno. No sumes `reasoning_tokens` otra vez a `output_tokens` ni
`cached_tokens` a `input_tokens`: son desgloses. No conviertas caracteres a
tokens para presentar un dato como exacto. [Detalles de las métricas](performance.md).

La caché de prompts depende del prefijo compartido. Mantener instrucciones,
herramientas e historial previo estables puede favorecer su reutilización;
reescribir resultados antiguos o insertar contenido dinámico al principio puede
romperla. Agent Shell recorta cada resultado nuevo una vez y conserva ese texto
en las solicitudes posteriores. No se garantiza un acierto de caché ni un
descuento concreto sobre tu plan. [OpenAI Docs: prompt caching](https://developers.openai.com/api/docs/guides/prompt-caching).

## Reglas para desarrollar el harness

1. Mantén separados los mensajes de interfaz, el contexto del proveedor y los
   archivos generados. Los visores y sus animaciones no deben añadir tokens.
2. Conserva el orden de los elementos de Responses y la relación `call_id` entre
   llamada y resultado. No ejecutes argumentos parciales durante streaming.
   [OpenAI Docs: function calling](https://developers.openai.com/api/docs/guides/function-calling).
3. Con `store: false`, conserva el razonamiento cifrado que devuelve el proveedor
   junto con el resultado de las herramientas. No lo sustituyas por texto visible
   ni lo borres al recortar logs. [OpenAI Cookbook: reasoning items](https://developers.openai.com/cookbook/examples/responses_api/reasoning_items).
4. Guarda antes de ejecutar una orden y guarda el resultado antes de llamar de
   nuevo al modelo. Recuperar historial nunca debe ejecutar una orden pendiente.
5. Cancela HTTP y el grupo de procesos usando el mismo turno. Rechaza eventos
   tardíos de una generación anterior. EOF de stdout no significa fin del proceso.
6. No reintentes automáticamente un comando con efectos ni una solicitud de
   inferencia ambigua. Para recuperación de red hacen falta reglas explícitas
   de idempotencia, espera y presupuesto; hoy se conserva el estado y se informa.
7. Prueba tanto éxito como evidencia de fallo: cola del log, timeout, cancelación,
   salida cerrada, falta de uso reportado, límite y recuperación sin reejecución.
8. Evalúa ahorro y calidad juntos. Un recorte que borra el diagnóstico y provoca
   tres consultas nuevas puede salir más caro que conservar información útil.

Ejecuta `./scripts/check.sh` y, cuando cambie la integración con Qt,
`./scripts/smoke.sh`. Usan procesos y HTTP locales con datos simulados. La
compatibilidad y el ahorro efectivos en una cuenta real requieren una medición
separada; las pruebas locales no consumen esa cuenta.

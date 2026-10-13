# Rendimiento por respuesta

[← Índice de documentación](../README.md)

Cada turno aceptado registra tiempos locales y conteos. Debajo del último
mensaje de la respuesta aparece un resumen discreto, por ejemplo
`2.30 s · Media: 45.5 tok/s`; pulsarlo abre el desglose. El contexto aparece junto
a **Enviar**, por ejemplo `Contexto: 12.4k tokens`, y también abre sus detalles
al pulsarlo. Los valores del ejemplo son ilustrativos. El indicador del editor
usa la última medición del chat abierto y se recupera al cargar el historial;
se oculta si no hay datos, corresponden a otro modelo seleccionado o está
ejecutándose `/shell`. El editor conserva su altura al mostrarlo u ocultarlo.
La velocidad sólo aparece cuando está disponible; los caracteres por segundo
quedan como alternativa con su unidad explícita cuando falta la media en tokens.
Si falla antes de recibir texto, la medición queda junto al mensaje de usuario.
Durante la espera también se muestra un contador de tiempo transcurrido.

El botón **Rendimiento** abre los últimos 200 turnos medidos de todos los chats.
Permite filtrar por modelo, consultar cada medición y comparar medianas. El p95
del tiempo total se muestra desde 20 respuestas completadas sin terminal y con tiempo conocido;
usa el método de rango más cercano. Los fallos y las interrupciones se cuentan
aparte y no entran en las estadísticas de latencia. Los turnos en curso tampoco.
Los turnos con comandos se muestran por separado y no entran en medianas ni p95:
su duración total incluye ejecución de shell y espera de confirmación.

## Qué se mide

El backend usa `time.perf_counter()`, un reloj monotónico, y expresa duraciones
en milisegundos. El origen es la recepción de `chat.send`, antes de tomar el
bloqueo del servidor. Los tiempos no son etapas independientes que deban sumarse:
algunos se solapan.

| Campo | Definición |
| --- | --- |
| `prepare_ms` | Recepción del turno → contexto listo y trabajador por iniciar; incluye guardar el mensaje y publicar historial |
| `session_ms` | Tiempo en obtener el token propio; incluye bloqueo, lectura y renovación si corresponde |
| `headers_ms` | Inicio de la solicitud HTTP → cabeceras recibidas; incluye DNS, TLS, red y servicio |
| `first_text_ms` | Recepción del turno → primer contenido no vacío de la respuesta en el backend |
| `request_first_text_ms` | Inicio HTTP → primer texto; combina red y servicio, sin atribuirlo sólo al modelo |
| `total_ms` | Recepción del turno → procesamiento del evento terminal, error o cancelación; excluye el guardado final y la presentación posterior en Qt |
| `elapsed_ms` | Tiempo transcurrido o duración congelada cuando termina |
| `stream_ms` | Primer texto → final del turno o momento de la actualización |
| `first_visible_ms` | Enviar en Qt → siguiente notificación `frameSwapped` tras recibir el primer texto; aproximación de presentación |
| `ui_frame_ms` | Recepción del primer texto en Qt → esa notificación de fotograma |
| `characters` | Caracteres Unicode del texto recibido, reconciliado por item y parte; el texto final no duplica deltas |
| `characters_per_second` | Caracteres añadidos después del primer fragmento / tiempo entre el primer y último cambio de texto |
| `context_messages`, `input_characters` | Mensajes visibles y sus caracteres al iniciar el turno; excluye instrucciones, llamadas, resultados de herramientas y razonamiento cifrado |
| `usage` | Conteos reales que entrega OpenAI: entrada, salida, total, razonamiento y entrada en caché, cuando existen |
| `context_tokens` | `input_tokens` de la última llamada terminada del turno, sin sumar solicitudes; desconocido si esa llamada no lo reporta o hay otra en curso |
| `model_request_ms` | Suma de intervalos inicio HTTP → evento terminal de cada llamada; al cancelar o fallar el transporte conserva el tiempo parcial observado |
| `tokens_per_second` | Tokens de salida reportados por todas las llamadas / suma de sus tiempos HTTP en segundos; sólo en turnos completados con conteos y tiempos de todas las llamadas y al menos 100 ms acumulados |
| `model_calls` | Número de solicitudes al modelo iniciadas durante el turno |
| `tool_calls` | Número de comandos solicitados, incluidos los rechazados o inválidos |
| `tool_ms` | Suma de duración de ejecuciones de shell terminadas |
| `approval_ms` | Espera de confirmaciones de versiones anteriores; cero en turnos nuevos con ejecución automática |

Las duraciones desconocidas son `null` y se presentan como **—**, nunca como
cero. La velocidad en caracteres requiere al menos 100 ms entre cambios de texto; una respuesta
de un solo fragmento o una ráfaga muy breve no ofrece una velocidad útil. Describe
texto recibido por el cliente, no la velocidad interna del servidor.
En turnos con herramientas la velocidad en caracteres se deja sin dato para evitar mezclar
fragmentos de distintas solicitudes con esperas del usuario. La media en tokens
sí puede mostrarse, porque cronometra las llamadas HTTP por separado y excluye
terminal, persistencia entre llamadas y sesión/renovación. Incluye latencia de
red, razonamiento, procesamiento del servicio y recepción local; no mide su velocidad interna
ni sólo el texto visible. Los fragmentos SSE no se cuentan como tokens.

El contexto corresponde a la entrada de la última llamada medida, que puede
incluir historial, instrucciones, definiciones de herramientas y resultados de
ejecuciones de IA. No representa un saldo ni un porcentaje de la capacidad del
modelo, ni cuenta la respuesta generada después de esa entrada. El conteo exacto
queda en los detalles; el resumen abrevia miles con `k`.

Las dos medidas de Qt usan diferencias de `Date.now()` dentro de la interfaz.
Son aproximadas, pueden verse afectadas por ajustes del reloj y la cola de señales,
y no miden la presentación física del monitor. No se restan relojes de procesos
distintos. Si la ventana no presenta un fotograma, esos campos quedan sin dato.
El resumen prefiere `first_visible_ms` cuando existe y usa `first_text_ms` como
alternativa. Las comparaciones por modelo siempre usan el tiempo del backend.

Los tokens se extraen de `usage` del evento terminal y se muestran sólo si OpenAI
los entrega. Los tokens de salida pueden incluir razonamiento y otros elementos
no visibles. La media usa ese conteo completo, sin restar razonamiento ni
convertir caracteres a tokens.
En turnos con herramientas se suman los conteos reportados por las solicitudes;
si alguna no entrega uso, esa suma puede ser parcial y la media en tokens queda
sin dato. Los detalles separan **Contexto de la última llamada** de **Consumo
acumulado reportado del turno**, con entrada, salida, total, razonamiento y caché.
Los tiempos de sesión y
cabeceras corresponden a la primera solicitud. La duración de ejecución y espera
de una llamada interrumpida puede quedar parcial o en cero si no llegó a terminar.
No se infiere consumo contando fragmentos y no se calcula saldo ni coste de la suscripción.
Referencia: [eventos de Responses en OpenAI Docs](https://developers.openai.com/api/reference/resources/responses/streaming-events).

## Persistencia y compatibilidad

El array opcional `performance` vive en el JSON de cada conversación, con una
medición por `turn_id`. Los mensajes nuevos tienen `turn_id` para asociar texto
y medición. Se mantiene `schema_version: 1`: los chats anteriores siguen abriendo
y sus respuestas antiguas aparecen sin métricas. Los tres campos nuevos son
opcionales: no se deduce contexto ni velocidad en tokens de registros anteriores.

Las mediciones guardan modelo, fecha, estado, conteos y duraciones. No añaden
prompts, texto de respuesta, tokens OAuth ni diagnósticos HTTP. Se escriben junto
con el historial existente; las actualizaciones durante streaming se emiten como
máximo cada 250 ms, además de primer texto y estados inicial/final, y no provocan
una escritura por fragmento. La confirmación de Qt recibida después de terminar
guarda una actualización adicional para conservar los tiempos de la interfaz.

Errores, cancelaciones y cierre normal conservan mediciones parciales. Después
de un cierre forzado, un registro guardado en curso se presenta como interrumpido
y su duración es el último tiempo observado, no la duración exacta del cierre.
Datos opcionales de rendimiento incompatibles se omiten sin ocultar mensajes.

## Comparar resultados

Usa el mismo modelo, mensaje, instrucciones y contexto en varias solicitudes.
Considera el tamaño de la respuesta, la renovación de sesión y la caché de entrada.
La mediana resume el comportamiento habitual; el p95 ayuda a observar respuestas
lentas. Veinte muestras habilitan el indicador, pero una comparación fiable
necesita más observaciones en condiciones similares.

El panel recopila el uso normal. Abrirlo o actualizarlo consulta archivos locales;
no inicia un benchmark ni envía solicitudes adicionales a OpenAI.

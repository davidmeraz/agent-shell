# Rendimiento por respuesta

Cada turno aceptado registra tiempos locales y conteos. Debajo del último
mensaje de la respuesta aparece un resumen y **Detalles** abre el desglose.
Si falla antes de recibir texto, la medición queda junto al mensaje de usuario.
Durante la espera también se muestra un contador de tiempo transcurrido.

El botón **Rendimiento** abre los últimos 200 turnos medidos de todos los chats.
Permite filtrar por modelo, consultar cada medición y comparar medianas. El p95
del tiempo total se muestra desde 20 respuestas completadas con tiempo conocido;
usa el método de rango más cercano. Los fallos y las interrupciones se cuentan
aparte y no entran en las estadísticas de latencia. Los turnos en curso tampoco.

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
| `context_messages`, `input_characters` | Número de mensajes y caracteres del contexto enviado, sin contar las instrucciones fijas |
| `usage` | Conteos reales que entrega OpenAI: entrada, salida, total, razonamiento y entrada en caché, cuando existen |

Las duraciones desconocidas son `null` y se presentan como **—**, nunca como
cero. La velocidad requiere al menos 100 ms entre cambios de texto; una respuesta
de un solo fragmento o una ráfaga muy breve no ofrece una velocidad útil. Describe
texto recibido por el cliente, no la velocidad interna del servidor.

Las dos medidas de Qt usan diferencias de `Date.now()` dentro de la interfaz.
Son aproximadas, pueden verse afectadas por ajustes del reloj y la cola de señales,
y no miden la presentación física del monitor. No se restan relojes de procesos
distintos. Si la ventana no presenta un fotograma, esos campos quedan sin dato.
El resumen prefiere `first_visible_ms` cuando existe y usa `first_text_ms` como
alternativa. Las comparaciones por modelo siempre usan el tiempo del backend.

Los tokens se extraen de `usage` del evento terminal y se muestran sólo si OpenAI
los entrega. Los tokens de salida pueden incluir razonamiento. No se infiere
consumo contando fragmentos y no se calcula saldo ni coste de la suscripción.
Referencia: [eventos de Responses en OpenAI Docs](https://developers.openai.com/api/reference/resources/responses/streaming-events).

## Persistencia y compatibilidad

El array opcional `performance` vive en el JSON de cada conversación, con una
medición por `turn_id`. Los mensajes nuevos tienen `turn_id` para asociar texto
y medición. Se mantiene `schema_version: 1`: los chats anteriores siguen abriendo
y sus respuestas antiguas aparecen sin métricas.

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

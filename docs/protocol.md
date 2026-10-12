# Protocolo de interfaz NDJSON v2

Contrato UTF-8 entre Qt y Python, con un objeto por línea y terminador `\n`.
Límite de línea de entrada Qt → Python: 65 536 bytes; mensaje de usuario: entre 1 y 16000 caracteres.
Este sobre no se envía a OpenAI: Python traduce las instrucciones a OAuth/HTTP.

Los comandos escritos con `/` se resuelven en Qt antes de enviar mensajes.
`/nuevo` y `/detener` usan `chat.new` y `chat.cancel`; `/historial` abre el panel
y solicita la lista cuando corresponde. `/ayuda` y `/terminal` abren controles
locales; `/modelos` muestra modelos dentro del editor sólo al completar ese
nombre. `/mode`, `/model` y `/modelo` son prefijos para sugerir completar el
comando, sin activar la selección. El editor no tiene selector de modelos.
Confirmar un modelo usa `model.select` con un slug validado del catálogo.
Aplicar configuración de terminal usa las instrucciones
existentes; ningún comando con `/` se traduce a `chat.send`.
`/shell comando` usa `shell.execute` con el texto de la orden, conservando comillas,
tuberías, saltos de línea y espacios finales. Completar el nombre prepara el
argumento y no ejecuta nada; un argumento vacío mantiene el borrador con un aviso.

## Instrucciones Qt → Python

| Tipo | Campos | Acción |
| --- | --- | --- |
| `chat.send` | `prompt` | Solicitar respuesta con los mensajes locales |
| `area.select` | `area: chat/work`, `project_id` opcional | Cambiar de área o proyecto y restaurar la conversación de la sesión |
| `project.create` | `name`: 1–80 caracteres, `workdir` | Registrar una carpeta existente y abrir su proyecto en Work |
| `projects.list` | Ninguno | Consultar los proyectos registrados sin contactar a OpenAI |
| `chat.cancel` | Ninguno | Cerrar streaming o detener shell local; conservar el texto y la salida parcial |
| `chat.new` | Ninguno | Vaciar conversación actual |
| `chat.open` | `chat_id` | Cargar conversación local |
| `chat.delete` | `chat_id` | Borrar el archivo local del chat y sus mediciones |
| `shell.configure` | `workdir` | Validar y cambiar el directorio local, sólo fuera de un turno; la terminal permanece disponible |
| `shell.execute` | `command`: entre 1 y 8000 caracteres, sin NUL | Ejecutar directamente en el directorio configurado, sin autenticación ni modelo |
| `history.list` | Ninguno | Consultar conversaciones recientes del área o proyecto seleccionado |
| `auth.login` | `new_account` booleano opcional, por defecto `false` | Reautorizar la cuenta seleccionada o registrar otra |
| `auth.select` | `account_id` del registro guardado | Activar otra cuenta y actualizar modelos |
| `auth.cancel` | Ninguno | Cancelar el intento OAuth |
| `auth.refresh` | Ninguno | Leer sesión y actualizar catálogo |
| `auth.logout` | Ninguno | Revocar y cerrar la sesión local |
| `model.select` | `model` | Seleccionar un slug del catálogo de la cuenta |
| `performance.list` | Ninguno | Consultar los últimos 200 turnos medidos de todos los chats, sin llamadas a OpenAI |
| `performance.presented` | `turn_id`, `first_visible_ms`, `ui_frame_ms` | Confirmar la aproximación de presentación del primer texto en Qt |

Sólo una respuesta, ejecución local u operación de cuenta a la vez. El historial puede leerse sin
autenticación y mientras se descubre el catálogo. Cambiar de chat se rechaza
durante respuesta o login, al igual que borrar conversaciones. Cerrar stdin cancela operaciones y cierra el backend.

La interfaz pide confirmación antes de enviar `chat.delete`. El backend valida el
identificador y rechaza enlaces simbólicos. Sólo después de eliminar el archivo
emite `chat.deleted`, seguido de `history.list` y `performance.list` actualizados.
Si era el chat abierto, primero limpia el contexto y emite `chat.reset`; las
confirmaciones de presentación y respuestas tardías no recrean el archivo.
Un archivo inexistente o un fallo de borrado produce `error` y conserva el estado
actual. El borrado funciona sin sesión y no hace llamadas a OpenAI.

## Eventos Python → Qt

Cada evento contiene `version: 2`, `seq` creciente, `timestamp` UTC ISO 8601,
`type`, `run_id: null` y `data`. La secuencia se serializa entre trabajadores.

| Tipo | Datos |
| --- | --- |
| `backend.ready` | `provider: chatgpt`, `app_version` |
| `backend.disconnected` | `message` |
| `area.state` | `area: chat/work`, `project`: registro del proyecto seleccionado o `null` |
| `area.rejected` | `message`: selección o registro rechazado; el área activa se conserva |
| `projects.list` | `projects`: project_id, name, workdir, fechas y schema_version |
| `history.ready` | `directory` absoluto |
| `history.list` | `chats`: chat_id, title, updated_at, area y project_id |
| `history.notice` | `message` de persistencia |
| `auth.state` | `authenticated`, `method`, `email`, `plan`, `plan_enabled`, `accounts` |
| `auth.login.started` | `url` OAuth, para abrir el navegador; nunca registrarla |
| `auth.login.finished` | `success`, `message`, `show_plan_welcome` |
| `auth.refresh.started` | Objeto vacío |
| `auth.refresh.finished` | Objeto vacío |
| `models.list` | `models`: slug y display_name; `selected` |
| `model.selected` | `model`: slug |
| `chat.busy` | `turn_id` del mensaje de usuario y la medición |
| `chat.thread` | `thread_id`: id del chat local; `model` |
| `chat.saved` | `chat_id`, `title` |
| `chat.loaded` | `chat`: registro visible con mensajes, métricas y herramientas; excluye `context` |
| `chat.deleted` | `chat_id` de la conversación local eliminada |
| `shell.state` | `enabled: true`, `workdir` absoluto, `timeout_seconds` |
| `shell.started` | `turn_id` de la ejecución local |
| `shell.finished` | `turn_id`, `status: completed/error/timeout/interrupted`, `message` |
| `shell.rejected` | `message`: petición local inválida, ocupada o que no pudo guardarse; no altera la ejecución activa |
| `tool.updated` | `call`: id local, call_id del proveedor o local, turn_id, command, workdir, status, output, exit_code, truncated, message_index y duration_ms si terminó; source opcional `local` para `/shell` |
| `chat.delta` | `item_id`, `text` que amplía el mensaje, `turn_id` |
| `chat.message` | `item_id`, `text` final que reemplaza fragmentos, `turn_id` |
| `chat.finished` | `status: completed/failed/interrupted`, `message`, `turn_id` |
| `performance.updated` | `measurement`: instantánea del turno con `chat_id` |
| `performance.list` | `measurements`: últimas 200 instantáneas, más recientes primero |
| `chat.reset` | Objeto vacío |
| `error` | `message` apto para mostrar al usuario |

`authenticated` significa que existe una sesión con permiso para usar el plan,
no sólo una identidad verificada. `plan` queda vacío si no hay información
verificada sobre su nombre. Enviar requiere además un modelo disponible.
Una actualización fallida no cierra el backend ni elimina los mensajes.
`shell.execute` funciona sin autenticación ni catálogo de modelos. Guarda la
llamada antes de iniciar el proceso y publica salida mediante `tool.updated`.
Usa los límites y la cancelación del ejecutor compartido. No emite `chat.busy`,
mensajes de IA ni `performance.updated`, y no hace peticiones al proveedor.
Los resultados con `source: local` se conservan sólo en `tool_calls`; no se añaden
al `context` de Responses. Si no hay conversación, crea una titulada con `/shell`
y el comando. Abrir ese historial restaura tarjetas sin ejecutar sus órdenes.

`accounts` contiene `{id, label, email, active}` por registro verificado; nunca
tokens ni clientes OAuth. `id` es estable, opaco y válido para `auth.select`.
La cuenta seleccionada puede necesitar reautorización: usa `auth.login` sin
`new_account`. Registrar otra cuenta conserva las anteriores y sólo la activa
tras validar la identidad; cerrar sesión afecta únicamente a la seleccionada.
Las operaciones de cuenta se bloquean durante respuestas u otra operación de
autenticación y usan los eventos existentes `auth.refresh.started/finished`.

Un texto final puede llegar sin deltas previos. Un mensaje usa item_id y parte
de contenido para reconciliarse sin duplicados. Recibir texto final no confirma
el éxito del turno: eso lo indica `chat.finished`. Eventos tardíos de respuestas
canceladas se descartan.

El registro del chat tiene un array opcional `performance`, compatible con los
chats anteriores. Las instantáneas contienen identidad del turno, modelo, fecha,
estado, tiempos en milisegundos, caracteres, contexto y uso de tokens disponible.
Un campo desconocido es `null`; no se transforma en cero. Las definiciones exactas
de cada campo están en [rendimiento](performance.md). Los campos opcionales
`context_tokens`, `model_request_ms` y `tokens_per_second` añaden el contexto de
la última llamada y la velocidad media observada en tokens. La velocidad requiere
un turno completado y tiempos/conteos conocidos para todas sus llamadas; excluye
ejecución de shell y no sustituye `usage`, que conserva el consumo acumulado.
Los registros anteriores presentan esos campos como `null`. Es una ampliación
compatible del protocolo v2 y del historial con esquema 1.

`chat.loaded.chat.tool_calls` conserva los comandos y sus resultados visibles.
`message_index` ubica cada tarjeta antes del mensaje de ese índice. Los estados
son `pending`, `running`, `completed`, `error`, `timeout`, `denied`, `interrupted`.
Una llamada pendiente recuperada se marca como interrumpida sin ejecutarla.
El `context` opcional del JSON contiene elementos de Responses y razonamiento
cifrado para continuar; se excluye de `chat.loaded` y de todos los eventos Qt.

La herramienta shell se anuncia en todas las respuestas y se usa cuando la tarea
lo requiere. Las llamadas estructuradas válidas se ejecutan automáticamente, sin
decisiones de aprobación ni filtros de comandos. Se guardan antes de crear el
proceso y se publican mediante `tool.updated`. `chat.cancel` termina el grupo del
proceso activo, además del streaming HTTP. Cambiar el directorio no inicia procesos
ni solicitudes al modelo. Sus límites se documentan en [terminal](terminal.md).

`performance.presented` sólo se acepta para el turno actual con texto recibido,
con tiempos finitos y no negativos, `ui_frame_ms <= first_visible_ms` y un límite
de 24 horas. Se acepta una sola confirmación, también después de terminar para
guardar el dato de Qt. Los identificadores de turnos anteriores se ignoran.
`performance.list` funciona sin sesión y durante una respuesta; se lee en un
trabajador y la medición activa se toma de memoria para evitar datos atrasados.

El protocolo v2 elimina `tool.decide`, `tool.approval` y `tool.approval.resolved`.
`shell.configure` deja de permitir desactivar la herramienta y sólo configura
el directorio. Backend e interfaz deben actualizarse juntos. El historial mantiene
`schema_version: 1`, incluidos los resultados y estados de versiones anteriores.

## Áreas y proyectos

`area.select` con `area: work` y sin `project_id` restaura el último proyecto usado
durante la sesión; si todavía no hay uno, abre la pantalla de proyectos. Un
`project_id: ""` explícito abre esa pantalla. `area: chat` restaura la conversación
general y su directorio inicial o configurado. Cada proyecto guarda en memoria su
conversación abierta al salir; sus JSON permiten abrir las conversaciones después
de reiniciar. Se rechaza el cambio o registro durante respuesta, ejecución, login
o actualización de cuenta. Seleccionar una carpeta inexistente no modifica el estado.

`project.create` valida el nombre y resuelve la carpeta existente; rechaza otra
identidad para la misma carpeta. El registro se escribe privadamente y de forma
atómica en `projects/`, dentro del directorio del historial, separado de los JSON
de conversaciones y de las credenciales. No modifica los archivos del proyecto.
`shell.configure` en Work actualiza también la carpeta persistida del proyecto;
en Chat cambia sólo su directorio. Work sin proyecto no admite respuestas ni shell.

Los registros de conversaciones añaden `area` y `project_id` al esquema 1. Los
anteriores se interpretan como `area: chat, project_id: ""`. El historial se filtra
por ambos campos; abrir o borrar un identificador de otra área se rechaza. El
contexto enviado a OpenAI sigue procediendo exclusivamente de la conversación
actual. Las métricas globales conservan su alcance de todos los chats. Estas son
ampliaciones compatibles del protocolo v2: no se eliminan instrucciones ni eventos.

En 0.3.0 cambian el proveedor de backend.ready y el significado de thread_id:
identifica una conversación local y ya no un thread de Codex. Los cambios de
opciones CLI se documentan en el README y en el historial de cambios.

Las credenciales y el razonamiento no se publican. La única URL OAuth enviada
al cliente sirve para abrir el navegador; puede incluir un id_token_hint durante
reautorización y debe tratarse como información privada.

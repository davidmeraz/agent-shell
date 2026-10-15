# Protocolo de interfaz NDJSON v2

[← Índice de documentación](../README.md)

Contrato UTF-8 entre Qt y Python, con un objeto por línea y terminador `\n`.
Límite de línea de entrada Qt → Python: 8 MiB; mensaje de usuario: hasta 16000 caracteres,
con texto no vacío o una imagen válida.
Este sobre no se envía a OpenAI: Python traduce las instrucciones a OAuth/HTTP.

Los comandos escritos con `/` se resuelven en Qt antes de enviar mensajes.
`/nuevo` y `/detener` usan `chat.new` y `chat.cancel`; `/historial` abre el panel
y solicita la lista cuando corresponde. `/ayuda` y `/terminal` abren controles
locales; `/modelos` muestra familias dentro del editor sólo al completar ese
nombre. `/mode`, `/model` y `/modelo` son prefijos para sugerir completar el
comando, sin activar la selección. El editor no tiene selector de modelos.
El recorrido es familia → modelo → esfuerzo; no aplica cambios durante los pasos
intermedios ni al completar con Tab. Acepta `/modelos gpt-6 modelos` para listar
la familia y `/modelos gpt-6 gpt-6.1-sol high` para la selección completa.
Conserva `/modelos slug [esfuerzo]`. Confirmar usa `model.select` con un slug
y esfuerzo validados del catálogo; `auto` se transforma en la cadena vacía.
Aplicar configuración de terminal usa las instrucciones
existentes; ningún comando con `/` se traduce a `chat.send`.
`/shell comando` usa `shell.execute` con el texto de la orden, conservando comillas,
tuberías, saltos de línea y espacios finales. Completar el nombre prepara el
argumento y no ejecuta nada; un argumento vacío mantiene el borrador con un aviso.

## Instrucciones Qt → Python

| Tipo | Campos | Acción |
| --- | --- | --- |
| `chat.send` | `prompt`, `image` opcional | Solicitar respuesta con texto y, opcionalmente, una imagen como URL de datos base64 |
| `clipboard.paste` | `request_id`: 1–128 caracteres | Leer una imagen del portapapeles gráfico en un trabajador, sin inferencia |
| `area.select` | `area: chat/work`, `project_id` opcional | Cambiar de área o proyecto y restaurar la conversación de la sesión |
| `project.create` | `name`: 1–80 caracteres, `workdir` | Registrar una carpeta existente y abrir su proyecto en Work |
| `project.delete` | `project_id` | Eliminar registro e historiales válidos del proyecto, conservando su carpeta local |
| `explorer.list` | `project_id`, `request_id`, `path` relativa (vacía para raíz) | Listar una carpeta del proyecto activo o el último de Work conservado en Chat, sin inferencia |
| `explorer.read` | `project_id`, `request_id`, `path` relativa | Leer vista previa UTF-8 del proyecto activo o el último de Work conservado en Chat |
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
| `model.select` | `model`, `reasoning_effort` opcional: nivel admitido o `""` para Auto | Selección atómica; si falta el esfuerzo conserva el actual para el mismo modelo y usa Auto al cambiarlo; persiste en la conversación abierta |
| `performance.list` | Ninguno | Consultar los últimos 200 turnos medidos de todos los chats, sin llamadas a OpenAI |
| `usage.read` | `request_id`: 1–128 caracteres | Consultar cuotas de la sesión ChatGPT de Codex, sin inferencia |
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

La interfaz también confirma `project.delete` e informa que la carpeta local se
conserva. Se rechaza durante una respuesta, shell, login o actualización de cuenta.
El backend valida el identificador y los registros, aparta los JSON privados y
restaura los traslados si falla la operación. Los historiales dañados o enlaces
simbólicos se conservan porque no permiten atribuir con certeza el proyecto.
Si se elimina el proyecto activo, se vuelve a la lista de Work, se invalida su
contexto y se limpian sus visores. Después emite `project.deleted` con los chats
retirados, seguido de listas actualizadas de proyectos, historial y rendimiento.
Qt descarta también borradores y adjuntos del proyecto. El borrado no necesita
que su carpeta exista y no contacta a OpenAI.

## Eventos Python → Qt

Work admite además `{"type":"project.run","project_id":"…"}` y
`{"type":"project.run.stop","project_id":"…","execution_id":"…"}`.
El inicio exige el proyecto activo y ausencia de otra
ejecución o turno de chat en curso; el prompt pertenece al backend y no admite
argumentos de texto/comando desde Qt. Detener valida ambos identificadores para
evitar cancelar una ejecución posterior. El programa admite conversación y cambios
de área simultáneos, mantiene su carpeta y se cancela al cerrar el backend.
El proyecto que se ejecuta no puede eliminarse. No cambia el historial ni crea
mensajes, herramientas conversacionales o mediciones. Son ampliaciones compatibles
de NDJSON v2; `execution_id` viaja en `data`, separado del `run_id` del sobre.
La detección requiere sesión/modelo disponibles; un inicio guardado válido puede
ejecutarse sin autenticación. Si la configuración cambia o la orden guardada falla,
se invalida y se vuelve a detectar una vez. Sin sesión se informa el impedimento.
Los proyectos visibles incluyen `has_launch_profile` como indicación de inicio
guardado, aún sujeto a comprobar su huella al ejecutar; excluyen `launch_profile`.

Cada evento contiene `version: 2`, `seq` creciente, `timestamp` UTC ISO 8601,
`type`, `run_id: null` y `data`. La secuencia se serializa entre trabajadores.

| Tipo | Datos |
| --- | --- |
| `backend.ready` | `provider: chatgpt`, `app_version` |
| `backend.disconnected` | `message` |
| `clipboard.result` | `request_id`, `image`: URL de datos o cadena vacía; `message` opcional si falló |
| `area.state` | `area: chat/work`, `project`: registro del proyecto seleccionado o `null` |
| `area.rejected` | `message`: selección, registro o borrado rechazado; el área activa se conserva |
| `project.deleted` | `project_id`, `chat_ids`: conversaciones locales eliminadas con el proyecto |
| `projects.list` | `projects`: project_id, name, workdir, fechas y schema_version |
| `history.ready` | `directory` absoluto |
| `history.list` | `chats`: chat_id, title, updated_at, area y project_id |
| `history.notice` | `message` de persistencia |
| `auth.state` | `authenticated`, `method`, `email`, `plan`, `plan_enabled`, `accounts` |
| `auth.login.started` | `url` OAuth, para abrir el navegador; nunca registrarla |
| `auth.login.finished` | `success`, `message`, `show_plan_welcome` |
| `auth.refresh.started` | Objeto vacío |
| `auth.refresh.finished` | Objeto vacío |
| `usage.started` | `request_id` |
| `usage.state` | `request_id`, `source: codex`, `account: {email, plan}`, `limits`, `summary` opcional y `checked_at` UTC |
| `usage.error` | `request_id`, `code`, `message` local apto para mostrar |
| `usage.finished` | `request_id`: libera el estado de consulta de la interfaz |
| `models.list` | `models`: `slug`, `display_name`, `family`, `reasoning_efforts` y `default_reasoning_effort`; `selected`, `reasoning_effort` activo |
| `model.selected` | `model`: slug; `reasoning_effort`: selección explícita o `""` para Auto |
| `project.run.state` | `execution_id`, `project_id`, `model`, `reasoning_effort`, `workdir`, `phase: preparing/inspecting/starting/running/stopping/completed/failed/interrupted`, `command`, `output`, `exit_code`, `message`, `source: ai/cache`, `cache_available`; `duration_ms` y `truncated` al terminar el programa |
| `project.run.cache` | `project_id`, `available`: actualiza la disponibilidad del inicio guardado, sin publicar su perfil privado |
| `project.run.rejected` | `project_id`, `message`: inicio o detención inválidos; no modifica la ejecución activa ni añade mensajes al chat |
| `chat.busy` | `turn_id` del mensaje de usuario y la medición |
| `chat.thread` | `thread_id`: id del chat local; `model` |
| `chat.saved` | `chat_id`, `title` |
| `chat.loaded` | `chat`: registro visible con mensajes, métricas y herramientas; excluye `context` |
| `chat.deleted` | `chat_id` de la conversación local eliminada |
| `shell.state` | `enabled: true`, `workdir` absoluto, `timeout_seconds` para `/shell`, `agent_timeout_seconds` opcional para comandos de la IA |
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

`usage.read` usa un trabajador independiente y puede ejecutarse durante una
respuesta o shell. Rechaza otra consulta en curso, login o actualización de
cuenta; requiere una sesión activa de Agent Shell. Codex debe tener una sesión
ChatGPT con correo coincidente. La coincidencia no verifica el espacio de trabajo
SIWC: los datos corresponden al espacio seleccionado en Codex, identificado como fuente.
No crea conversaciones, no modifica métricas de turnos ni usa el evento `error`.

Cada límite contiene `{id, name, primary, secondary, credits}`. Las ventanas son
`null` o `{used_percent, window_minutes, resets_at}`; cada dato no informado es
`null`, y `resets_at` usa segundos Unix. Los créditos, si existen, incluyen
`{unlimited, has_credits, balance}`; balance desconocido es `null`. El resumen
opcional contiene `lifetime_tokens`, acumulación registrada por Codex que no se
interpreta como consumo de todas las funciones de ChatGPT. No se incluyen tokens
de autenticación, identificadores privados ni el texto original de errores RPC.
Cambiar la cuenta activa invalida la vista; Qt usa `request_id` para descartar
respuestas de consultas anteriores. Un error borra los datos mostrados y
`usage.finished` permite reintentar. La interfaz sólo consulta periódicamente
mientras la ventana esté visible.
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
de cada campo están en [rendimiento](../guides/performance.md). Los campos opcionales
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
ni solicitudes al modelo. Sus límites se documentan en [terminal](../guides/terminal.md).

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

## Imágenes y portapapeles

`chat.send.image` admite exclusivamente una URL `data:image/png;base64,...`,
`data:image/jpeg;base64,...` o `data:image/webp;base64,...`. El backend valida base64,
formato real y dimensiones con Pillow, con límites de 4 MiB decodificados y
16 megapíxeles. No lee rutas ni descarga URLs externas. `prompt` puede estar vacío
si hay una imagen válida. Una petición nueva durante un turno se rechaza mediante
`error` antes de validar la imagen, sin terminar la respuesta activa.

Los mensajes del historial añaden `image` opcional sólo al rol `user`. El contexto
de Responses combina `input_text` e `input_image` con `detail: auto`; la imagen
continúa en el contexto de los siguientes turnos y no se cuenta como caracteres
de texto en las métricas. Qt muestra una miniatura en el editor y la imagen enviada
en la conversación, y conserva el adjunto del borrador por área durante la sesión.

`clipboard.paste` no necesita autenticación y usa `wl-paste` en Wayland o `xclip`
en X11. Acota la lectura por tamaño y tiempo; jamás interpreta contenido como
comandos. Qt correlaciona `request_id`, bloquea pegados duplicados y descarta una
respuesta después de quitar el adjunto, enviar, cargar otro chat o cambiar de área.
El pegado de texto sigue siendo nativo. Las imágenes no se adjuntan a comandos `/`.
Estos campos y eventos son ampliaciones compatibles del protocolo v2 y del
historial con esquema 1.

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

## Explorador de Work

Ampliación compatible de v2. Las lecturas funcionan sin sesión y durante una
respuesta o shell; no cambian conversación, directorio ni historial. Sólo se
aceptan solicitudes para el proyecto activo en Work o, mientras está seleccionado
Chat, para el último proyecto de Work de esta sesión. En Chat se carga y valida
su registro; las lecturas se anclan a su carpeta, no al directorio del chat. Otros
proyectos y registros eliminados o inválidos se rechazan. `request_id` es una cadena
de hasta 128 caracteres y `path` una cadena de hasta 4096, sin NUL, rutas absolutas
ni componentes `..`. No se siguen enlaces simbólicos en ningún componente;
las carpetas excluidas por el explorador tampoco son accesibles por solicitud.

Respuestas, siempre con `project_id` y `request_id` para correlación:

- `explorer.list`: `path`, `entries`, `truncated`. Cada entrada incluye `name`,
  `path` relativa, `directory` booleano, `size` y `modified_ns` como cadena para
  conservar precisión en JavaScript. Carpetas primero, nombres ordenados sin
  distinguir mayúsculas. Máximo 1000 entradas por carpeta.
- `explorer.file`: `path`, `text`, `truncated`. Archivo regular, texto UTF-8,
  máximo 128 KiB. NUL o codificación inválida se rechazan; un fragmento truncado
  puede sustituir un carácter UTF-8 cortado en el límite.
- `explorer.error`: `message`, y `path` cuando corresponde; no usa el evento
  genérico `error`, para no afectar el estado de turnos o cuenta.

Qt separa el árbol y hasta dos visores de texto en ventanas independientes,
sin modificar el contrato. Cada una consulta cada 1500 ms sólo mientras está
visible: el árbol usa `explorer.list` y los visores `explorer.read`. Los identificadores
del árbol tienen prefijo `explorer-`; cada visor incluye su número del 1 al 2 y una
secuencia creciente en `file-viewer-N-secuencia`, para no mezclar respuestas.
Un archivo ya abierto conserva su visor; nuevos archivos ocupan un visor libre.
Con dos visores visibles, el tercer archivo muestra un aviso local, sin solicitar
lectura ni reemplazar contenido. Cerrar una ventana descarta sus solicitudes pendientes y no
cierra ni detiene la otra. Seleccionar otro archivo invalida la lectura anterior;
las respuestas con un identificador no pendiente o de otro proyecto se descartan.
Qt mantiene el contexto del explorador (`project_id`, nombre y carpeta) separado
del área activa del chat. Pasar a Chat y regresar al mismo proyecto conserva
ventanas, carpetas expandidas, contenido y sondeo. Cambiar de proyecto o su carpeta
limpia el árbol y cierra los archivos; Work sin proyecto, `project.deleted` para el
contexto mostrado y desconexión del backend limpian ese contexto y cierran las ventanas.
Las marcas de cambios son locales al
árbol y no prueban autoría de la IA. El sondeo manual no consulta carpetas plegadas
ni ofrece un registro persistente de modificaciones. El seguimiento de herramientas
de IA se describe a continuación.

### Seguimiento del trabajo de la IA

Eventos compatibles adicionales de NDJSON v2, sólo en Work durante comandos de
la IA; no se producen para `/shell`, conversaciones de Chat ni lecturas del historial:

- `work.activity`: `project_id`, `call_id` (identificador local de la tarjeta de
  herramienta), `turn_id`, `status`: `running`, `completed`, `error`, `timeout`
  o `interrupted`. Inicia o termina la observación de un comando.
- `work.changed`: los mismos identificadores y `action`: `created`, `modified`
  o `deleted`; `path` relativa, `directory` booleano y `sequence` creciente por
  comando. Un archivo regular UTF-8 puede incluir `preview` con `path`, `text`
  y `truncated`, bajo los mismos límites y confinamiento de `explorer.file`.
  Los archivos binarios se señalan en el árbol sin abrir un visor de texto.
- La variante `work.changed` con `action: "notice"` lleva `message` y los
  identificadores del comando, sin ruta ni secuencia: el seguimiento alcanzó
  un límite o no está disponible; el comando y el sondeo siguen funcionando.

Los cambios se observan en disco durante el comando; no prueban la identidad del
proceso escritor. inotify agrupa cambios de la misma ruta durante aproximadamente
180 ms y drena los pendientes al terminar. Hasta 1024 carpetas, 1000 entradas por
listado inicial y 512 rutas pendientes; ráfagas grandes muestran seguimiento parcial.
El historial privado y las carpetas excluidas no se observan. No se guardan estos
eventos ni se reenvían al modelo.

Qt abre el árbol automáticamente, expande las carpetas afectadas y muestra los
dos archivos de texto más recientes, reutilizando los visores cuando están ocupados.
Invalida lecturas anteriores antes de aplicar una instantánea y anima el resaltado
del cambio, conservando el texto real. La instantánea completa es el destino del
visor; el documento visible revela progresivamente el intervalo nuevo, con cursor
y la indicación «Mostrando cambios». Es una animación local de contenido ya recibido,
sin eventos nuevos ni cambios en shell. Actualizaciones sucesivas reemplazan ese
destino. Cancelar, cerrar o eliminar el archivo completa la última vista y detiene
la animación; terminar correctamente permite completar la presentación pendiente.
Los eliminados muestran la última vista.
Se descartan eventos de otra área, proyecto, comando, secuencia anterior o comando
terminado. `chat.finished` también detiene el seguimiento al cancelar o fallar;
el servidor invalida callbacks del turno cancelado. El sondeo de las ventanas
permanece activo al terminar, sin seguimiento persistente en segundo plano.

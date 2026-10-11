# Protocolo de interfaz NDJSON v1

Contrato UTF-8 entre Qt y Python, con un objeto por línea y terminador `\n`.
Límite de línea de entrada Qt → Python: 65 536 bytes; mensaje de usuario: entre 1 y 16000 caracteres.
Este sobre no se envía a OpenAI: Python traduce las instrucciones a OAuth/HTTP.

## Instrucciones Qt → Python

| Tipo | Campos | Acción |
| --- | --- | --- |
| `chat.send` | `prompt` | Solicitar respuesta con los mensajes locales |
| `chat.cancel` | Ninguno | Cerrar streaming y conservar el texto parcial |
| `chat.new` | Ninguno | Vaciar conversación actual |
| `chat.open` | `chat_id` | Cargar conversación local |
| `chat.delete` | `chat_id` | Borrar el archivo local del chat y sus mediciones |
| `history.list` | Ninguno | Consultar conversaciones recientes |
| `auth.login` | Ninguno | Iniciar OAuth propio de ChatGPT |
| `auth.cancel` | Ninguno | Cancelar el intento OAuth |
| `auth.refresh` | Ninguno | Leer sesión y actualizar catálogo |
| `auth.logout` | Ninguno | Revocar y cerrar la sesión local |
| `model.select` | `model` | Seleccionar un slug del catálogo de la cuenta |
| `performance.list` | Ninguno | Consultar los últimos 200 turnos medidos de todos los chats, sin llamadas a OpenAI |
| `performance.presented` | `turn_id`, `first_visible_ms`, `ui_frame_ms` | Confirmar la aproximación de presentación del primer texto en Qt |

Sólo una respuesta o operación de cuenta a la vez. El historial puede leerse sin
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

Cada evento contiene `version: 1`, `seq` creciente, `timestamp` UTC ISO 8601,
`type`, `run_id: null` y `data`. La secuencia se serializa entre trabajadores.

| Tipo | Datos |
| --- | --- |
| `backend.ready` | `provider: chatgpt`, `app_version` |
| `backend.disconnected` | `message` |
| `history.ready` | `directory` absoluto |
| `history.list` | `chats`: chat_id, title y updated_at |
| `history.notice` | `message` de persistencia |
| `auth.state` | `authenticated`, `method`, `email`, `plan`, `plan_enabled` |
| `auth.login.started` | `url` OAuth, para abrir el navegador; nunca registrarla |
| `auth.login.finished` | `success`, `message`, `show_plan_welcome` |
| `auth.refresh.started` | Objeto vacío |
| `auth.refresh.finished` | Objeto vacío |
| `models.list` | `models`: slug y display_name; `selected` |
| `model.selected` | `model`: slug |
| `chat.busy` | `turn_id` del mensaje de usuario y la medición |
| `chat.thread` | `thread_id`: id del chat local; `model` |
| `chat.saved` | `chat_id`, `title` |
| `chat.loaded` | `chat`: registro local completo |
| `chat.deleted` | `chat_id` de la conversación local eliminada |
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

Un texto final puede llegar sin deltas previos. Un mensaje usa item_id y parte
de contenido para reconciliarse sin duplicados. Recibir texto final no confirma
el éxito del turno: eso lo indica `chat.finished`. Eventos tardíos de respuestas
canceladas se descartan.

El registro del chat tiene un array opcional `performance`, compatible con los
chats anteriores. Las instantáneas contienen identidad del turno, modelo, fecha,
estado, tiempos en milisegundos, caracteres, contexto y uso de tokens disponible.
Un campo desconocido es `null`; no se transforma en cero. Las definiciones exactas
de cada campo están en [rendimiento](performance.md).

`performance.presented` sólo se acepta para el turno actual con texto recibido,
con tiempos finitos y no negativos, `ui_frame_ms <= first_visible_ms` y un límite
de 24 horas. Se acepta una sola confirmación, también después de terminar para
guardar el dato de Qt. Los identificadores de turnos anteriores se ignoran.
`performance.list` funciona sin sesión y durante una respuesta; se lee en un
trabajador y la medición activa se toma de memoria para evitar datos atrasados.

El formato de eventos sigue en v1. Los eventos y campos nuevos son aditivos.
En 0.3.0 cambian el proveedor de backend.ready y el significado de thread_id:
identifica una conversación local y ya no un thread de Codex. Los cambios de
opciones CLI se documentan en el README y en el historial de cambios.

Las credenciales y el razonamiento no se publican. La única URL OAuth enviada
al cliente sirve para abrir el navegador; puede incluir un id_token_hint durante
reautorización y debe tratarse como información privada.

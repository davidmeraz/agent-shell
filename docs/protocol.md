# Protocolo de interfaz NDJSON v1

Este contrato comunica Qt con Python y es distinto del protocolo RPC oficial de
Codex App Server. UTF-8, un objeto por línea y terminador `\n`. Límite de línea:
65 536 bytes; mensaje de usuario: entre 1 y 16000 caracteres.

## Instrucciones Qt → Python

| Tipo | Campos adicionales | Acción |
| --- | --- | --- |
| `chat.send` | `prompt` | Iniciar respuesta en el thread actual o crear uno |
| `chat.cancel` | Ninguno | Interrumpir la respuesta activa |
| `chat.new` | Ninguno | Vaciar conversación y descartar contexto actual |
| `chat.open` | `chat_id` | Cargar una conversación local para verla y continuarla |
| `history.list` | Ninguno | Consultar las conversaciones recientes |
| `auth.login` | Ninguno | Iniciar OAuth de ChatGPT administrado por Codex |
| `auth.cancel` | Ninguno | Cancelar el inicio de sesión |
| `auth.refresh` | Ninguno | Consultar otra vez la cuenta, sin forzar refresh de tokens |

Sólo una respuesta o inicio de sesión a la vez. El cliente limita el envío según
estado; el servidor también valida. Cancelar sin operación activa no cambia el chat.
Una instrucción inválida produce `error`. El cierre de stdin termina App Server.

## Eventos Python → Qt

Cada evento contiene `version: 1`, `seq` creciente, `timestamp` UTC ISO 8601,
`type`, `run_id: null` y `data`. Los identificadores de conversación y mensaje
están en `data`; `run_id` queda reservado para posibles ejecuciones futuras.

| Tipo | Datos |
| --- | --- |
| `backend.ready` | `provider: codex`, `app_version` SemVer |
| `backend.disconnected` | `message` |
| `history.ready` | `directory` absoluto del historial; habilita lectura local |
| `history.list` | `chats`: lista de `chat_id`, `title` y `updated_at`, reciente primero |
| `history.notice` | `message` sobre archivos dañados o fallas de guardado |
| `auth.state` | `authenticated`, `method`, `email`, `plan` |
| `auth.login.started` | `url` OAuth; sólo para abrir navegador, no guardarla en logs |
| `auth.login.finished` | `success`, `message` |
| `chat.busy` | Objeto vacío |
| `chat.thread` | `thread_id`, `model` |
| `chat.saved` | `chat_id`, `title` de la conversación actual |
| `chat.loaded` | `chat`: registro JSON completo con mensajes y metadatos |
| `chat.delta` | `item_id`, `text` para ampliar el mensaje |
| `chat.message` | `item_id`, `text` final que reemplaza los deltas |
| `chat.finished` | `status: completed/failed/interrupted`, `message` |
| `chat.notice` | `message` informativo del proveedor |
| `chat.reset` | Objeto vacío |
| `error` | `message` de instrucción o llamada RPC rechazada |

Un mensaje final puede llegar sin deltas previos. El cliente debe crearlo en ese
caso. La cancelación conserva el texto parcial ya recibido. `chat.finished` con
`completed` confirma éxito; `failed` e `interrupted` liberan controles sin anunciar éxito.
Un error informativo no debe por sí solo marcar como terminada una respuesta activa.
`history.ready` y `history.list` se publican antes de iniciar Codex. `chat.open`,
`chat.new` y `history.list` funcionan sin autenticación ni conexión; `chat.send`
continúa requiriéndolas. Abrir o cambiar de chat se rechaza durante un turno activo.
Los eventos adicionales mantienen la versión de protocolo 1; los consumidores
deben ignorar tipos desconocidos de esa misma versión.

Los eventos de otros threads se ignoran. No se reenvían tokens, mensajes internos
ni razonamiento. La secuencia se serializa globalmente aunque participen varios hilos.

## Evolución del contrato

Este es el contrato inicial del chat. Los cambios incompatibles deberán incrementar
`version` y actualizar ambos extremos, siguiendo la política SemVer de la aplicación.
El App Server de Codex mantiene su propio esquema: no interpreta este sobre NDJSON.

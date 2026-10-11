# Arquitectura del chat

Agent Shell mantiene su propia sesión de ChatGPT y conecta directamente con
OpenAI. Quickshell inicia únicamente el backend Python; no hay proceso de Codex.

```mermaid
flowchart LR
    Qt[Chat Qt Quick] --> Bridge[AgentBridge]
    Bridge -->|NDJSON v1| Python[HarnessServer]
    Python --> Session[Sesión OAuth local]
    Python --> Client[Cliente ChatGPT]
    Session -->|OAuth y claves públicas| Auth[auth.openai.com]
    Client -->|HTTPS y SSE| API[Responses API con permiso de plan]
    API -->|Fragmentos de texto| Client
    Python --> History[Historial JSON local]
    Python -->|Llamada validada y aprobada| Shell[Ejecutor local de shell]
    Shell -->|Salida y estado| Python
```

## Responsabilidades

- `ChatWindow`: chat, cuenta, modelo, control de respuesta e historial.
- `AgentBridge`: aplica eventos, reconcilia texto final por identificador y abre
  la autorización sólo al solicitar el usuario iniciar sesión.
- `HarnessServer`: valida instrucciones, construye contexto local, coordina
  operaciones en trabajadores y emite el contrato NDJSON.
- `ChatGPTSession`: registro dinámico de cliente, callback loopback, validación
  de identidad, permisos, persistencia y renovación.
- `HttpClient`: HTTPS verificado sin redirecciones automáticas, errores sin
  diagnósticos privados, lectura SSE y cierre de sockets al cancelar.
- `ChatGPTClient`: descubre modelos de la cuenta y solicita respuestas.
- `ShellExecutor`: ejecuta comandos aprobados, acota la salida y termina grupos de procesos.
- `context.py`: conserva elementos de Responses y cierra llamadas recuperadas sin reejecutarlas.
- `HistoryStore`: metadatos y mensajes en JSON atómico.
- `TurnPerformance`: reloj monotónico, etapas del turno, conteos y uso reportado por OpenAI.
- `Performance.js`: formato de métricas y estadísticas por modelo en Qt.
- `EventEmitter`: secuencia global y escritura serializada entre trabajadores.

## Autenticación

Antes de autorizar se crea un host estable, `ext_agent_host_id`, independiente de
la identidad de usuario. El registro inicial usa `dynamic_agent_client`, nombre
`Agent Shell`, scopes de identidad y permiso `chatgpt.tokens.use.direct`.
Las nuevas conexiones usan el cliente emitido por OpenAI, asociado a esa cuenta.
La implementación actual mantiene una sola cuenta registrada por directorio de
sesión; un selector de cuentas queda pendiente.

Cada intento tiene state, nonce y PKCE nuevos. El listener está ligado únicamente
a `127.0.0.1` y a `/auth/callback`. El intercambio usa exactamente el mismo URI,
incluyendo puerto. Un callback con state incorrecto no consume el intento válido.

Se verifica la firma RS256 del ID token con JWKS de OpenAI, emisor, audiencia,
vencimiento, nonce y sujeto. Una reautorización no puede sustituir la identidad de
la cuenta. Sólo el permiso concedido de plan habilita inferencia.

El archivo de sesión contiene el host, cliente, identidad verificada y tokens.
Las renovaciones se serializan con un bloqueo entre procesos, reemplazando tokens
rotativos atómicamente. Los ajustes de Codex nunca se leen ni se modifican.

## Inferencia y contexto

El catálogo viene de `GET https://api.openai.com/v1/models` con el token OAuth.
Se muestran entradas con `visibility: list`, se conserva su orden y se envía el
`slug` del modelo seleccionado. No hay un modelo de pago independiente como fallback.

Cada turno envía instrucciones y los mensajes locales mediante
`POST https://api.openai.com/v1/responses`, con `store: false` y `stream: true`.
Con Terminal activada se anuncia la función `shell`; el backend espera confirmación
antes de ejecutarla y devuelve el resultado con su `call_id` para continuar.
Los fragmentos y el texto final se reconcilian por
item y parte de contenido. Sólo `response.completed` con estado confirmado
marca el final de una solicitud al modelo. Si contiene herramientas, el turno
continúa hasta la respuesta final o un límite, rechazo o cancelación.
Fallos, respuestas incompletas y cortes de conexión conservan el texto
parcial y liberan los controles.

Los JSON de 0.2.0 siguen siendo legibles. Su antiguo thread_id no se consulta:
continuar utiliza los mensajes locales. Si faltaba contexto interno, no puede
reconstruirse. Las conversaciones demasiado largas pueden superar el contexto;
todavía no hay compactación.

## Persistencia y ciclo de vida

Las mediciones se guardan en el array opcional `performance` del chat. Un `turn_id`
vincula mensajes y medición; una generación evita actualizaciones de turnos cancelados.
`StreamControl` informa inicio/fin de sesión, solicitud HTTP y cabeceras al servidor.
Qt confirma la aproximación de presentación del primer texto con `frameSwapped`.
Los eventos de rendimiento durante streaming se agrupan cada 250 ms sin añadir
escrituras por fragmento. El panel consulta como máximo 200 turnos de archivos locales.
Las definiciones y límites se describen en [rendimiento](performance.md).

El primer mensaje crea el chat y se guarda antes de solicitar inferencia. El
streaming actualiza Qt antes del guardado y agrupa escrituras cada medio segundo.
Al terminar, cancelar o recibir SIGTERM se guarda el estado final y el texto pendiente.

Cancelar cierra el socket de streaming y marca inmediatamente el turno como
interrumpido, cerrando también la aprobación y el grupo de shell activo.
Una generación impide que eventos tardíos contaminen el siguiente
turno. El backend sigue disponible después de errores de red para reintentar.
Cerrar stdin o SIGTERM cancela operaciones; los trabajadores de red tienen timeout.

El historial está separado de las credenciales. Puede leerse sin autenticación,
durante el descubrimiento del catálogo y si el archivo de sesión es incompatible.
La prueba Qt usa un backend real con cuenta de prueba y servicio HTTP local.
El usuario confirmó la autenticación real desde el escritorio. También se verificó
una respuesta real con el backend y la sesión propia de Agent Shell, hasta recibir
texto y `response.completed`.
La integración de shell también se comprobó con la sesión real: solicitud de
`pwd`, ejecución aprobada en una carpeta temporal y respuesta basada en su salida,
seguida de continuación desde ese contexto con la terminal desactivada.

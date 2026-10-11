# Agent Shell

Aplicación de chat para Linux con **Quickshell y Qt Quick**, sesión propia de
**ChatGPT** y respuestas progresivas. Se conecta directamente a OpenAI mediante
el flujo oficial **Sign in with ChatGPT** para aplicaciones locales.

**Versión: 0.4.0.** No requiere Codex CLI ni App Server.
Las etiquetas locales `v0.1.0`, `v0.2.0` y `v0.3.0` conservan las versiones anteriores.

## Preparar y ejecutar

Requisitos: Python 3.11+, Quickshell 0.3.x con Qt Quick Controls y Layouts, acceso
a Internet y una sesión gráfica. La validación de identidad usa PyJWT con
cryptography; la instalación prepara un entorno Python dentro del proyecto.

```bash
./scripts/setup.sh
./scripts/run.sh
```

Pulsa **Continuar con ChatGPT**, inicia sesión en el navegador y autoriza el uso
de tu plan. La cuenta debe ser elegible para esta integración; disponibilidad,
modelos y límites los determina OpenAI. Esta modalidad consume el uso autorizado
de tu plan, sin configurar una API key ni una facturación de API independiente.

La aplicación descubre los modelos disponibles para tu cuenta y permite elegirlos.
Usa **Enter** para enviar, **Shift+Enter** para un salto de línea, **Detener** para
interrumpir y **Nuevo chat** para otra conversación. Los mensajes se pueden copiar
y seleccionar; actualmente se presentan como texto sin formato Markdown.

**Administrar uso** abre los ajustes de ChatGPT. **Actualizar** renueva el
catálogo y consulta la sesión local. **Salir** cierra la sesión de Agent Shell e
intenta revocarla en OpenAI; si la revocación no se confirma, se informa para que
puedas desconectar la aplicación desde los ajustes de ChatGPT.

## Rendimiento

Cada respuesta muestra tiempo hasta el primer texto, duración y velocidad de
texto cuando hay una muestra suficiente. **Detalles** abre tiempos de preparación,
sesión, red y presentación en Qt, tamaño del contexto y tokens entregados por OpenAI.

**Rendimiento** reúne los últimos 200 turnos medidos de todos los chats. Permite
filtrar por modelo y comparar medianas y p95, con fallos y cancelaciones aparte.
Las mediciones quedan guardadas junto al historial y se recuperan al reiniciar.
Los tiempos de red incluyen el servicio y los de presentación son aproximados.
Consulta [definiciones y límites de las métricas](docs/performance.md).

## Sesión independiente

Agent Shell registra su propia conexión, recibe tokens OAuth y los renueva
automáticamente. No importa la sesión ni las credenciales de Codex ni el historial
de ChatGPT. Tras actualizar desde 0.2.0, debes conectar tu cuenta una vez aquí.

El flujo usa PKCE, state y nonce por intento. El callback escucha temporalmente
en `127.0.0.1`, en un puerto disponible, con un límite de diez minutos. La firma
del ID token se verifica con las claves públicas de OpenAI, junto con emisor,
audiencia, vencimiento e identidad de la cuenta. No se confunde iniciar sesión
con conceder permiso para consumir el plan.

La sesión se guarda por defecto en `.runtime/session/session.json`, con
directorio `0700` y archivo `0600`. Contiene credenciales: no lo compartas ni lo
incluyas en Git. La aplicación no las publica en el protocolo de la interfaz ni
en registros. Una URL de autorización puede contener un ID token de la sesión
anterior como pista de cuenta: tampoco debe registrarse o compartirse.

## Historial y contexto

Cada conversación se guarda automáticamente en un JSON de `.runtime/chats/`.
El panel **Historial** permite abrir chats anteriores, copiar la ubicación y abrir
la carpeta. El texto local sigue disponible sin conexión y sin iniciar sesión.

Las solicitudes llevan los mensajes guardados de la conversación y no dependen
de threads remotos. Se envían con `store: false` y `stream: true`. Los chats de
0.2.0 conservan su formato y pueden continuarse desde sus mensajes; el antiguo
`thread_id` queda como metadato y no se usa para pedir contexto a Codex.
No se recupera razonamiento ni contexto interno que no figure en el historial local.

Las escrituras son atómicas. Durante streaming se agrupan cada medio segundo al
recibir fragmentos; finalizar, cancelar o cerrar normalmente guarda el texto
pendiente. Un cierre forzado o un corte de energía puede perder los fragmentos
más recientes. Los archivos dañados se conservan y se omiten de la lista.

Una conversación muy larga puede superar el contexto del modelo. Se informa del
error para iniciar otro chat; aún no hay resumen automático ni compactación.

## Configuración

| Variable / opción del backend | Uso |
| --- | --- |
| `AGENT_SHELL_HISTORY_DIR` / `--history-root` | Directorio del historial |
| `AGENT_SHELL_SESSION_DIR` / `--session-root` | Directorio privado de sesión |
| `AGENT_SHELL_MODEL` / `--model` | Modelo inicial si aparece en el catálogo |
| `AGENT_SHELL_PYTHON` | Intérprete del backend, por defecto `.venv/bin/python` |

Las opciones anteriores `--codex-executable`, `--chat-root` y
`AGENT_SHELL_CODEX` fueron retiradas.
`AGENT_SHELL_BACKEND_ENTRY` permite a las pruebas seleccionar una entrada local
explícita; el lanzamiento normal usa `backend/main.py` y el servicio real.

## Comprobaciones

```bash
./scripts/check.sh
./scripts/smoke.sh
.venv/bin/python backend/main.py --version
```

Las pruebas de OAuth usan JWT firmados con claves de prueba. La integración HTTP
usa un servidor loopback de prueba y el cliente de streaming real. La integración
Qt offscreen comprueba cuenta, modelos, streaming, cancelación, historial,
presentación del primer texto y el panel de rendimiento.
Las pruebas automáticas no abren OAuth real ni consumen una cuenta. El usuario
confirmó el inicio de sesión real desde el escritorio. También se comprobó aparte
una solicitud real con el backend y la sesión propia de Agent Shell: recibió texto
y el evento `response.completed` de OpenAI.

## Estructura

```text
shell.qml                    Ventana principal
ui/AgentBridge.qml           Estado y contrato de eventos
ui/ChatWindow.qml            Chat, cuenta, modelos e historial
backend/main.py              Entrada del backend
backend/harness/auth.py      OAuth, identidad y sesión propia
backend/harness/http.py      HTTP y streaming SSE cancelable
backend/harness/chatgpt.py   Modelos e inferencia con tu plan
backend/harness/server.py    Traducción a eventos Qt y contexto local
backend/harness/history.py   Historial atómico compatible con 0.2.0
backend/harness/performance.py Tiempos y conteos por turno
ui/Performance.js            Formato y comparación de mediciones
tests/                       OAuth, HTTP y procesos de prueba
scripts/                     Instalación, ejecución y comprobaciones
```

Consulta [arquitectura](docs/architecture.md), [protocolo](docs/protocol.md),
[visión](docs/vision.md), [próximos pasos](docs/roadmap.md),
[versiones](docs/versioning.md), [historial de cambios](CHANGELOG.md) y
[contribución](CONTRIBUTING.md).

Referencias oficiales: [registro e inicio de sesión](https://developers.openai.com/siwc/token-sharing-open-source/sign-in),
[cuentas y renovación](https://developers.openai.com/siwc/token-sharing-open-source/profiles-and-sessions)
y [modelos e inferencia](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference).

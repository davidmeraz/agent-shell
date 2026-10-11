# Agent Shell

Aplicación de chat con ejecución local de shell para Linux, con **Quickshell y Qt Quick**, sesión propia de
**ChatGPT** y respuestas progresivas. Se conecta directamente a OpenAI mediante
el flujo oficial **Sign in with ChatGPT** para aplicaciones locales.

**Versión: 0.8.0.** No requiere Codex CLI ni App Server.
Las etiquetas locales `v0.1.0` a `v0.7.0` conservan las versiones anteriores.

## Preparar y ejecutar

Requisitos: Python 3.11+, Quickshell 0.3.x con Qt Quick Controls, Layouts y Effects, acceso
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

**Cuenta** reúne los controles de sesión. **Administrar uso del plan** abre los
ajustes de ChatGPT. **Actualizar cuenta** renueva el catálogo y consulta la sesión
local. **Salir** cierra la sesión de Agent Shell e
intenta revocarla en OpenAI; si la revocación no se confirma, se informa para que
puedas desconectar la aplicación desde los ajustes de ChatGPT.

Para cambiar de cuenta, abre **Cuenta → Usar otra cuenta** y elige la nueva
cuenta en el navegador. Se crea un registro separado y se conserva la anterior;
tras conectar varias, el selector permite volver a cualquiera. **Continuar con
ChatGPT** vuelve a autorizar la cuenta seleccionada. **Salir** cierra sólo esa
sesión. Tus conversaciones se conservan al cambiar de cuenta.

Si el navegador muestra `3p_login_workspace_scope_denied` al elegir otra cuenta,
cancela el intento en Agent Shell y usa **Usar otra cuenta**. Los registros
existentes están asociados a su cuenta y espacio de trabajo; no sirven para
autorizar una cuenta distinta. La nueva cuenta también debe ser elegible para
usar su plan con la aplicación.

## Comandos del chat

Escribe `/` para ver sugerencias compactas a la izquierda de **Enviar**, en el
espacio que ocupaba el selector de modelos. La fila mantiene una altura fija
al mostrar u ocultar las opciones, sin desplazar el chat ni el editor.
Usa **← / →** para elegir, **Enter** para ejecutar, **Tab** para completar
y **Esc** para ocultar las sugerencias.
También puedes escribir el comando completo y pulsar **Enviar**.

Al completar `/modelos` aparecen los modelos de tu cuenta en esa misma fila.
Mientras escribes `/mode`, `/model` o `/modelo`, sólo se sugiere completar el
comando; los modelos todavía no se muestran.
Puedes filtrarlos, por ejemplo con `/modelos gpt`, y elegir con **← / →** y
Enter o con un clic. Tab completa el
identificador del modelo sin cambiarlo hasta que confirmes.

| Comando | Acción |
| --- | --- |
| `/ayuda` | Mostrar los comandos disponibles |
| `/nuevo` | Preparar una conversación nueva; la anterior queda en el historial |
| `/historial` | Abrir las conversaciones guardadas |
| `/modelos` | Elegir modelo dentro del editor |
| `/terminal` | Abrir la configuración de terminal; no ejecuta ni activa comandos automáticamente |
| `/detener` | Cancelar la respuesta o ejecución en curso |

Se procesan localmente y no se envían a ChatGPT ni se guardan como mensajes.
`/modelos` acepta el identificador de un modelo; los demás no aceptan argumentos.
Un comando desconocido o no disponible muestra un aviso
y conserva el borrador. `/ayuda` y `/historial` funcionan sin sesión; elegir modelo
requiere una cuenta conectada. Puedes seguir escribiendo un borrador durante una
respuesta y usar `/detener`; el envío de mensajes espera a que termine el turno.

## Apariencia

La barra lateral reúne nuevo chat, historial, rendimiento y cuenta. Estos accesos
se concentran en ese panel. El centro muestra la conversación y el editor inferior
ofrece las acciones de envío y detención. Una etiqueta discreta a la izquierda de
Enviar muestra el modelo activo; al pasar el cursor indica su identificador y
recuerda el comando `/modelos`. Las sugerencias ocupan ese mismo espacio al usar
comandos, manteniendo estable la altura del editor.
El botón junto al título permite ocultar y mostrar la barra lateral. En ventanas
pequeñas la abre como un panel superpuesto, que puedes cerrar con **Cerrar** o **Esc**.
Las sugerencias de bienvenida preparan un mensaje que puedes editar antes de enviar.
El panel lateral, Historial, Cuenta, Rendimiento y sus diálogos usan el mismo vidrio
mate translúcido más marcado, con ondas de luz suaves que evocan un reflejo de agua.
Los reflejos se dibujan al cambiar el tamaño, sin animación continua.
Al abrir un panel superpuesto, el chat de detrás se
suaviza con [desenfoque de Qt Quick](https://doc.qt.io/qt-6/qml-qtquick-effects-multieffect.html);
ese efecto se activa sólo mientras hay un panel visible.
Con el renderizador de software se conserva el acabado mate sin desenfoque interno.

La interfaz usa únicamente blanco, negro y tonos de gris, con vidrio transparente,
un tinte oscuro y bordes de un píxel, con reflejos suaves.
El fondo principal tiene entre un 44 y un 48 % de opacidad para
dejar visible el escritorio. El campo de mensaje y los controles resaltan el foco
con un borde blanco. La selección de texto también es en blanco y negro.
El fondo solicita [desenfoque nativo de Quickshell](https://quickshell.org/docs/v0.3.0/types/Quickshell.Wayland/BackgroundEffect/)
en compositores compatibles con `ext-background-effect-v1`, como Hyprland reciente.
Sin ese soporte se conservan la transparencia y los bordes de cristal.

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

## Terminal con IA

Abre **Terminal** en la barra lateral, actívala, indica el directorio de trabajo y
pulsa **Aplicar**. Luego puedes pedir, por ejemplo: «Usa la terminal para decirme
en qué directorio estamos». Antes de ejecutar, la aplicación muestra el comando
exacto y su directorio: elige **Ejecutar** o **Rechazar**. **Esc** también rechaza.

La shell se ejecuta localmente con `/bin/sh -c`. La IA recibe el resultado real y
continúa la respuesta; el chat muestra comando, salida y estado en una tarjeta.
**Detener** cancela tanto la espera de confirmación como el proceso y su grupo.
La terminal comienza desactivada en cada lanzamiento y cada comando requiere
una confirmación nueva. Recuperar un chat no vuelve a ejecutar comandos guardados.

Cada comando tiene un máximo de 120 segundos y devuelve hasta 16000 caracteres
de stdout/stderr combinados. Un turno admite hasta ocho solicitudes al modelo y
ocho comandos, ejecutados en orden. No hay terminal interactiva ni gestión de
trabajos en segundo plano. El directorio es el punto de partida, no un aislamiento
del sistema: los comandos tienen los permisos de tu usuario. Su salida se comparte
con ChatGPT como parte de la conversación.

Consulta [diseño, permisos y límites de la integración](docs/terminal.md).

## Historial y contexto

Cada conversación se guarda automáticamente en un JSON de `.runtime/chats/`.
El panel **Historial** permite abrir chats anteriores, copiar la ubicación y abrir
la carpeta. El texto local sigue disponible sin conexión y sin iniciar sesión.
La papelera de cada chat, en la barra lateral o en Historial, permite borrar la
conversación después de confirmar. Se eliminan su archivo local, mensajes y
mediciones de rendimiento; no se puede deshacer. Si borras el chat abierto, queda
lista una conversación nueva. Durante una respuesta o un login, el borrado se
deshabilita. Un fallo al eliminar el archivo conserva el chat y muestra un error.

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
| `AGENT_SHELL_WORKSPACE` / `--workspace` | Directorio inicial de shell; también se puede cambiar desde Terminal |
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
presentación del primer texto, rendimiento, borrado y el ciclo de shell con
confirmación, ejecución real de `pwd` en una carpeta temporal y recuperación.
El escenario `commands-smoke.qml` comprueba los seis comandos, sugerencias
compactas, activación al completar `/modelos`, filtros, teclado y ratón,
validación y borradores sin sesión. Las comprobaciones
de comandos requieren el módulo QML QtTest, usado sólo en las pruebas.
Las pruebas automáticas no abren OAuth real ni consumen una cuenta. El usuario
confirmó el inicio de sesión real desde el escritorio. También se comprobó aparte
una solicitud real con el backend y la sesión propia de Agent Shell: recibió texto
y el evento `response.completed` de OpenAI.

## Estructura

```text
shell.qml                    Ventana principal
ui/AgentBridge.qml           Estado y contrato de eventos
ui/ChatWindow.qml            Chat, cuenta, modelos e historial
ui/components/ChatSidebar.qml Navegación y chats recientes
ui/components/ConversationPane.qml Mensajes y bienvenida
ui/components/MessageComposer.qml Editor, modelo y envío
ui/ChatCommands.js           Catálogo y validación de comandos locales
ui/components/CommandHelpDialog.qml Ayuda de comandos del chat
backend/main.py              Entrada del backend
backend/harness/auth.py      OAuth, identidad y sesión propia
backend/harness/http.py      HTTP y streaming SSE cancelable
backend/harness/chatgpt.py   Modelos e inferencia con tu plan
backend/harness/server.py    Traducción a eventos Qt y contexto local
backend/harness/history.py   Historial atómico compatible con 0.2.0
backend/harness/performance.py Tiempos y conteos por turno
backend/harness/shell.py      Validación, ejecución local y cancelación de procesos
backend/harness/context.py    Contexto de Responses y recuperación de llamadas
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

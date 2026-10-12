# Agent Shell

Aplicación de chat con ejecución local de shell para Linux, con **Quickshell y Qt Quick**, sesión propia de
**ChatGPT** y respuestas progresivas. Se conecta directamente a OpenAI mediante
el flujo oficial **Sign in with ChatGPT** para aplicaciones locales.

**Versión: 0.12.0.** No requiere Codex CLI ni App Server.
Las etiquetas locales `v0.1.0` a `v0.11.1` conservan las versiones anteriores.

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
y seleccionar; las respuestas presentan Markdown, tablas y bloques de código.

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

## Chat y Work

El selector **Chat | Work**, centrado arriba de la ventana, separa las conversaciones
generales del trabajo sobre proyectos. **Chat** conserva los chats anteriores.
**Work → Nuevo proyecto** vincula un nombre a una carpeta local existente, vacía o
con código. Puedes elegirla en el explorador o escribir su ruta.

Cada proyecto tiene sus conversaciones, comandos y contexto propios. La terminal
y `/shell` usan su carpeta; la IA recibe instrucciones para inspeccionar, implementar
y comprobar el trabajo solicitado. **Abrir carpeta** abre el proyecto en el explorador
y **Proyectos** permite elegir otro o registrar uno nuevo.

Cambiar de área o proyecto conserva la conversación abierta y el borrador durante
la sesión. Después de reiniciar, los proyectos siguen registrados y sus conversaciones
se recuperan desde su historial. El historial muestra sólo el área o proyecto actual;
**Rendimiento** sigue reuniendo las mediciones de todos los chats. La terminal permanece
disponible también en Chat. Las respuestas y comandos en curso deben terminar o detenerse
antes de cambiar de espacio.

## Explorador del proyecto

En **Work**, los visores acompañan automáticamente el trabajo de la IA: cuando
ejecuta una herramienta shell se abre el árbol; las carpetas afectadas se expanden
y los archivos de texto que crea o modifica aparecen en los dos visores. Si hay
más archivos, las ventanas rotan para mostrar los más recientes. También puedes
pulsar **Explorador** en la cabecera del proyecto. Se abre el
**visor de carpetas**, con un árbol expandible. Al seleccionar un archivo se abre
un **visor de archivos en otra ventana**, con texto UTF-8 de solo lectura que
puedes seleccionar y copiar. Puedes abrir **hasta dos visores de texto a la vez**:
cada archivo distinto ocupa una ventana libre, numerada del 1 al 2. Seleccionar
un archivo que ya está abierto conserva su visor, sin duplicarlo. Si los dos
están ocupados, aparece un aviso: cierra uno para abrir otro archivo, sin reemplazar
los que estás leyendo. Todas las ventanas tienen fondo de vidrio mate translúcido, reflejos suaves y
desenfoque nativo en compositores compatibles.

En Hyprland, al abrirlos se colocan como en la distribución de referencia:
**carpetas arriba a la izquierda**, **visor 1 alto a la derecha** y
**visor 2 abajo a la izquierda**. En un monitor de 2560 × 1440 con área útil
de 2540 × 1370, las medidas son 553 × 640, 781 × 1334 y 857 × 662,
respectivamente. La posición y
el tamaño se adaptan al monitor de la ventana y respetan las zonas reservadas
por barras. Al cerrar y reabrir una ventana se recupera esa disposición; seleccionar
un archivo ya abierto no lo mueve. No se modifica la configuración de Hyprland.
Se admiten los dispatchers Lua de Hyprland 0.55+ y las órdenes anteriores.
En otros compositores, la posición inicial la decide el gestor de ventanas.

Los visores muestran sólo la ruta, el contenido y un pie discreto: entradas
visibles en el árbol, o estado de solo lectura y líneas del archivo. Las rutas
completas aparecen al pasar el puntero; los archivos grandes indican vista parcial.
No hay títulos grandes ni botones de actualizar o cerrar. Arrastra la franja de
la ruta para mover la ventana y pulsa **Esc** o el atajo del compositor para cerrarla.
Puedes redimensionar y cerrar cada ventana por separado. Cerrar el árbol
no cierra los archivos ni detiene su actualización; cerrar un visor no cierra el
árbol ni los demás visores. Para reabrir un visor, selecciona un archivo en el árbol;
un nuevo cambio de la IA también puede reabrirlo automáticamente. Todas las ventanas
siguen disponibles mientras la IA o `/shell` trabaja.

Cada ventana se actualiza automáticamente cada 1,5 segundos mientras está visible.
El sondeo periódico del árbol sólo consulta la raíz y
las carpetas expandidas visibles, sin recorrer todo el proyecto; el visor consulta
únicamente su archivo abierto. Los archivos nuevos y modificados se marcan respecto
al último listado de su carpeta durante esa apertura del árbol; las marcas
del sondeo se reinician al reabrirlo; el seguimiento de la IA mantiene sus marcas
durante el trabajo. Las eliminaciones desaparecen del árbol y los renombrados
aparecen como eliminación y creación. Los cambios pueden venir de la IA o de otra
aplicación: no se atribuyen al modelo. Cambiar de área, proyecto o carpeta de
trabajo limpia los visores y cierra las ventanas de archivos; cambiar de área o
proyecto también cierra el árbol.

Esta base excluye `.git`, `.venv`, `venv`, `node_modules`, `__pycache__` y `.runtime`,
y no sigue enlaces simbólicos ni admite rutas fuera del proyecto. Cada listado
se limita a 1000 entradas y la vista previa a 128 KiB; los archivos binarios o
con otra codificación muestran un aviso. No incluye edición, diferencias ni
seguimiento persistente de cambios. El explorador funciona sin conectar una cuenta
y sus lecturas no se envían a la IA ni se guardan en el historial.

El seguimiento en vivo usa inotify durante cada comando de la IA, con cambios
agrupados aproximadamente cada 180 ms, hasta 1024 carpetas y 512 cambios pendientes.
Las vistas reciben instantáneas reales de hasta 128 KiB y resaltan suavemente los
cambios; una escritura por partes se ve progresivamente y una escritura de golpe
aparece completa. Se muestran estados de ejecución, finalización y cancelación;
un archivo eliminado conserva su última vista con un aviso. No se añade este
contenido al contexto ni al historial. `/shell` conserva su ejecución directa y
la actualización periódica de las vistas, sin activar el seguimiento automático.
El observador excluye el historial privado incluso si está dentro del proyecto.
Un límite o un fallo del observador se indica en el explorador y no impide ejecutar
el comando. Cambiar de área descarta los eventos anteriores.

Las ventanas aparecen con una transición breve de opacidad y desplazamiento del
contenido. Las carpetas y archivos nuevos entran suavemente, las flechas giran al
expandir carpetas y las filas se recolocan al añadir o eliminar entradas. El árbol
conserva sus filas durante las consultas para no repetir animaciones sin cambios.
Al escribir, el visor resalta el intervalo de líneas modificado y lo señala con una
barra lateral tenue; respeta el ajuste de línea y se adapta al redimensionar.
Cambiar de archivo tiene una transición independiente. El punto de actividad pulsa
sólo mientras la IA trabaja con la ventana visible; cerrar no espera a la animación.

## Imágenes en el chat

Copia una captura o imagen y pulsa **Ctrl+V** en el editor de Chat o Work. Aparece
una miniatura discreta que puedes quitar con **×**. Puedes enviarla sola o añadir
una descripción; una nueva imagen reemplaza la anterior. Los comandos locales
con `/` conservan el adjunto sin enviarlo a la IA. El pegado de texto sigue usando
el editor nativo de Qt.

Se admite una imagen PNG, JPEG o WebP por mensaje, de hasta **4 MiB y 16 megapíxeles**.
La imagen se conserva en el historial local y en el contexto de la conversación;
el borrador con su imagen se mantiene al cambiar de área durante la sesión.
Abrir otra conversación o preparar un nuevo chat descarta el adjunto pendiente.
Se necesita un modelo que admita imágenes. El envío usa `input_image` con una URL
de datos base64, según [OpenAI Docs](https://developers.openai.com/api/docs/guides/images-vision?api-mode=responses).

Para pegar imágenes, Wayland requiere **wl-clipboard** (`wl-paste`) y X11 requiere
**xclip**. La lectura tiene límites de tamaño y tiempo; las respuestas tardías del
portapapeles se descartan al cambiar de conversación o área.

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
| `/terminal` | Cambiar el directorio de la terminal, que permanece disponible; abrir este panel no ejecuta comandos |
| `/detener` | Cancelar la respuesta o ejecución en curso |
| `/shell comando` | Ejecutar directamente un comando local, por ejemplo `/shell pwd`, sin consultar a la IA |

Se procesan localmente y no se envían a ChatGPT ni se guardan como mensajes.
`/modelos` acepta el identificador de un modelo y `/shell` requiere un comando;
los demás no aceptan argumentos. Completar `/shell` prepara `/shell ` para escribir
la orden; la ejecución empieza al enviar el comando completo. Las sugerencias
se ocultan al escribir los argumentos.
Un comando desconocido o no disponible muestra un aviso
y conserva el borrador. `/ayuda`, `/historial` y `/shell` funcionan sin sesión; elegir modelo
requiere una cuenta conectada. Puedes seguir escribiendo un borrador durante una
respuesta y usar `/detener`; el envío de mensajes espera a que termine el turno.

## Apariencia

La barra lateral reúne nuevo chat, historial, rendimiento y cuenta. Estos accesos
se concentran en ese panel. El centro muestra la conversación y el editor inferior
ofrece las acciones de envío y detención. Una etiqueta discreta a la izquierda de
Enviar muestra el modelo activo y, a su lado, el estado de la respuesta; los textos
largos se recortan y pueden consultarse completos al pasar el cursor. El modelo
recuerda el comando `/modelos` al pasar el cursor. Las sugerencias ocupan ese mismo espacio al usar
comandos, manteniendo estable la altura del editor.
El chat no tiene cabecera con título ni estado de conexión. La barra lateral se
abre al mantener el puntero en los primeros 12 píxeles del borde izquierdo durante
160 ms y se oculta 450 ms después de salir del panel. Se superpone al chat sin
desplazar la conversación ni el editor, también en ventanas pequeñas.
**Ctrl+B** permite abrirla y cerrarla con el teclado; **Esc** también la cierra.
Al abrirla con el teclado permanece abierta para poder navegar por sus controles.
Los mensajes propios usan burbujas compactas y las respuestas muestran Markdown,
listas y bloques de código. Cada respuesta indica el modelo utilizado cuando la
medición está disponible, permite copiar el texto original con una confirmación
y muestra tiempo total y velocidad; al pulsar las métricas se abren sus detalles.
Mientras llega el primer texto aparece una indicación de espera. Al desplazarte
para leer mensajes anteriores, el chat conserva tu posición aunque llegue texto
nuevo; una flecha permite volver al último mensaje y reanudar el seguimiento.
Las barras de desplazamiento permanecen ocultas; puedes recorrer el contenido con
la rueda, gestos o teclado.
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

Cada respuesta muestra un resumen discreto con duración y velocidad media en
`tok/s`, cuando hay datos suficientes. El contexto de la última llamada aparece
junto a **Enviar**, con el conteo exacto al pasar el cursor y acceso al desglose
al pulsarlo. Se recupera al abrir una conversación del historial.
El contexto usa la entrada de la última llamada; el consumo del turno se acumula
por separado. La media usa los tokens de salida y el tiempo HTTP de todas las
llamadas a la IA: incluye red y razonamiento y excluye ejecución de terminal.
No se estima a partir de caracteres ni se muestra un porcentaje sin conocer el
límite del modelo. Los caracteres por segundo quedan como alternativa con su
unidad explícita cuando falta la velocidad en tokens. Pulsar el resumen abre
tiempos de preparación, sesión, red y presentación en Qt, contexto exacto y
consumo acumulado de entrada, salida, razonamiento y caché.

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

La terminal es una función principal y está siempre disponible desde el inicio.
La IA la usa cuando la tarea lo requiere; una conversación normal puede responderse
directamente. Todos los comandos se permiten y ejecutan automáticamente, sin
confirmación. Puedes pedir, por ejemplo: «Usa la terminal para decirme en qué
directorio estamos». **Terminal** en la barra lateral o `/terminal` permite cambiar
el directorio de trabajo y aplicar el cambio entre turnos.

Para ejecutar sin IA, escribe `/shell pwd`, `/shell ls -la` o `/shell git status`
en el chat. El resultado aparece en una tarjeta de **Terminal local**, con salida,
directorio, estado, duración y código de salida. Las tarjetas muestran una vista
compacta de las salidas largas, con opciones para ampliar y copiar toda la salida;
el directorio completo aparece al pasar el cursor por su ruta abreviada.
Funciona sin cuenta de ChatGPT y no genera
solicitudes al modelo ni mediciones de IA. El comando y su salida quedan en el
historial local, sin incorporarse al contexto que recibe la IA.

La shell se ejecuta localmente con `/bin/sh -c`. La IA recibe el resultado real y
continúa la respuesta; el chat muestra comando, salida y estado en una tarjeta.
Las instrucciones de la IA indican que, ante una petición simple de ejecutar un
comando, confirme brevemente el resultado sin repetir la salida de la tarjeta.
Si la tarea requiere análisis, interpreta los resultados sin transcribirlos;
un fallo, timeout o interrupción debe comunicarse como tal.
**Detener** cancela el proceso y su grupo, además de la respuesta en curso.
Recuperar un chat no vuelve a ejecutar comandos guardados.

Cada comando tiene un máximo de 120 segundos y devuelve hasta 16000 caracteres
de stdout/stderr combinados. Un turno admite hasta ocho solicitudes al modelo y
ocho comandos, ejecutados en orden. No hay terminal interactiva ni gestión de
trabajos en segundo plano. El directorio es el punto de partida, no un aislamiento
del sistema: los comandos tienen los permisos de tu usuario. Su salida se comparte
con ChatGPT cuando la ejecución la solicita la IA; `/shell` conserva su salida local.
Cada envío usa un proceso independiente: `cd` no cambia el directorio de envíos
posteriores. Usa `/terminal` para cambiarlo o combina, por ejemplo,
`/shell cd carpeta && pwd`.

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
ejecución automática real de `pwd` en una carpeta temporal y recuperación.
El escenario `commands-smoke.qml` comprueba los siete comandos, sugerencias
compactas, activación al completar `/modelos`, filtros, teclado y ratón,
validación y borradores sin sesión. `conversation-smoke.qml` comprueba Markdown,
copia, métricas y desplazamiento sin saltos, con las barras ocultas.
`shell-command-smoke.qml` verifica `/shell` desde el editor sin sesión: completado,
salida real, argumentos, errores, cancelación e historial. `workspaces-smoke.qml`
comprueba el selector centrado, registro y validación de proyectos, conversaciones
y borradores separados, y ejecución de shell en las carpetas de dos proyectos.
Las comprobaciones
de comandos requieren el módulo QML QtTest, usado sólo en las pruebas.
`images-smoke.qml` comprueba Ctrl+V, miniaturas, envío con o sin texto,
historial, cambio de modelo y adjuntos del borrador entre áreas. Usa un PNG
de prueba y un lector inyectado sólo en `tests/fake_backend.py`; no toca el
portapapeles del usuario. Las pruebas unitarias comprueban por separado los
lectores Wayland/X11, límites binarios y formato multimodal.
`activity-smoke.qml` comprueba herramientas de IA por HTTP con comandos reales:
apertura automática, carpetas, escritura por partes, animación, rotación de visores,
renombrado, eliminación, reapertura, cancelación y aislamiento entre áreas.
Las pruebas automáticas no abren OAuth real ni consumen una cuenta. El usuario
confirmó el inicio de sesión real desde el escritorio. También se comprobó aparte
una solicitud real con el backend y la sesión propia de Agent Shell: recibió texto
y el evento `response.completed` de OpenAI.

## Estructura

```text
shell.qml                    Ventana principal
ui/AgentBridge.qml           Estado y contrato de eventos
ui/ChatWindow.qml            Áreas Chat / Work, cuenta, modelos e historial
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

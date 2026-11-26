# Historial de cambios

Las versiones del proyecto siguen [SemVer 2.0.0](https://semver.org/lang/es/).
Cada versión identificada corresponde a una etiqueta Git anotada `vX.Y.Z`.

## Sin publicar

## [0.28.0] — 2026-11-25

Esta versión renueva la experiencia visual y operativa de **Agent Shell** con terminal rápida integrada estilo Linux, explorador nativo de carpetas, rediseño minimalista del compositor, barra lateral, perfil y visor Git, e iconos vectoriales fijos Gema.

- **Terminal rápida estilo Linux** (`QuickTerminalWindow.qml`, `server.py`): ventana flotante simétrica con prompt inline y foco automático, ejecución aislada con `ShellControl` sin contaminar el chat, autocompletado de rutas y comandos con `Tab` (`terminal.complete`) y comandos cortos `work [nombre]` y `app [nombre] [rust|python]`.
- **Visor de flujo Git refinado** (`GitFlowWindow.qml`): cabecera simétrica sin barra de filtro, botones alineados, commits minimalistas con tipo/ámbito sin duplicar y metadatos a la derecha, paleta cian hielo (`#7dd3fc`) en lugar del amarillo, animaciones suaves al desplegar detalle y panel interactivo de cambios locales con badges de estado y apertura directa de archivos.
- **Compositor de mensajes y paleta de comandos Gema** (`MessageComposer.qml`): botones circulares simétricos, auto-expansión del prompt, cursor luminoso Gema con estela y micro-onda al escribir, paleta de comandos con píldoras e indicadores `Tab`/`↵`, y botón dedicado para abrir la terminal rápida.
- **Gestión de chats y barra lateral minimalista** (`ChatSidebar.qml`, `history.py`): botón `+` al pie de la lista de conversaciones, renombrado en vivo de chats (`chat.rename`), títulos compactos y limpieza de acciones redundantes.
- **Espacios Work y App unificados y explorador nativo** (`WorkProjects.qml`, `GlassFolderDialog.qml`, `ProjectDialog.qml`): tarjetas minimalistas unificadas entre Work y App con tarjeta `+`, botón directo para iniciar/probar apps e instalar lanzador `.desktop`, conservación de la vista al cambiar de pestaña y nuevo diálogo nativo `GlassFolderDialog` (`fs.list` / `fs.mkdir`).
- **Perfil, uso, visor de imágenes e iconos vectoriales** (`ChatWindow.qml`, `ImagePreviewWindow.qml`, `UnifiedTeamWindow.qml`, `GemaIcon.qml`): ventana de perfil y cuenta rediseñada, botón para mostrar/ocultar uso de crédito expandiendo la ventana principal, panel de equipo unificado como ventana flotante opcional en Ajustes, visor de imágenes centrado sin bordes e iconos vectoriales fijos `GemaIcon` inmunes a mutaciones de símbolo al cambiar tema en Hyprland.

## [0.27.0] — 2026-11-23

Esta versión incorpora el modo unificado con arquitecto y obreros, los motores Claude Code y Antigravity, y su configuración persistente.

- Modo unificado con arquitecto, obreros y uso por proveedor, y ventanas de agente.
- Configuración persistente del modo unificado en `unified.json` (`backend/harness/work/unified_config.py`): cascada de arquitectos, umbral de cuota, obreros en paralelo y ranuras de obreros, con el diálogo `UnifiedConfigDialog.qml`.
- Motores Antigravity CLI (Gemini/Claude) y Claude Code CLI con selector superior de tres motores.
- Runtime nativo Qt/Hyprland, dock inferior con cuota por chat y diálogo unificado de **Ajustes**.
- Botón **Git** y visor lateral del flujo de commits en **Work** y **App**; mejoras de desplazamiento, ámbito e indentación en el visor de archivos.
- Corrección del bloqueo al reabrir historiales largos.
- Botón **Archivos** junto a **Git** en **Work** y **App** para abrir o cerrar el explorador del proyecto seleccionado.

## [0.26.0] — 2026-11-22

Esta versión incorpora la vista de iconos grandes como modo predeterminado del explorador de archivos junto al selector rápido para alternar entre iconos grandes y vista en árbol.

- Nuevo componente `ui/components/windows/ExplorerIconCard.qml`: tarjetas interactivas de vidrio mate armonizadas con `GemaTheme`, con iconos vectoriales grandes de carpeta (pestaña, hojas interiores con micro-animación al pasar el cursor y brillo especular), iconos grandes de archivo con esquina doblada, líneas estilizadas e insignia de lenguaje, número de visor abierto (`#1`/`#2`) y píldoras de cambio (`Creado`, `Nuevo`, `Mod.`).
- Selector de vista dual en `ui/components/windows/ProjectExplorerWindow.qml`: vista de iconos grandes (`⊞`, predeterminada, `Ctrl+1`) con cuadrícula adaptable, barra de navegación por ruta (*breadcrumbs*), botón `←` / tecla Retroceso y seguimiento automático de la carpeta afectada durante actividad de la IA, más vista en árbol compacta (`≡`, `Ctrl+2`).
- Pruebas UI actualizadas en `tests/ui/explorer-smoke.qml` y `tests/ui/activity-smoke.qml` para validar la vista predeterminada de iconos grandes, cierre con `Esc`, animaciones de entrada y estabilidad de delegados, verificadas con `qmllint` y `./scripts/smoke.sh`.

## [0.25.0] — 2026-11-22

Esta versión renueva las ventanas de código (`ProjectFileWindow.qml`) y carpetas (`ProjectExplorerWindow.qml`) con resaltado de sintaxis multi-lenguaje adaptado dinámicamente al tema principal Gema y una animación fluida de generación de código en vivo.

- Nuevo motor ligero de sintaxis y armonía cromática `ui/js/CodeSyntax.js` conectado a `GemaTheme.codePalette`: genera automáticamente una paleta armónica (análogos, complementarios divididos y compensación de luminosidad perceptual para vidrio oscuro y `darkText`) a partir del color de acento activo de Hyprland/Gema, con soporte para QML, JS/TS, Python, Rust, Shell, JSON, Markdown (incluidos bloques cercados), HTML/XML/SVG, CSS/QSS, TOML/YAML/CONF, C/C++/Go/Java y SQL manteniendo `TextEdit.PlainText` para selección y copia exactas.
- Animación de escritura progresiva mejorada en `FileWriteReveal.qml` y `ProjectFileWindow.qml`: refresco a 60 fps (`16 ms`) con curva en S y duración sublineal (`460 ms`–`2650 ms`), barra de progreso luminosa sobre el separador especular, numeración de líneas sincronizada con el ajuste de línea (`Canvas` anclado al viewport), haz de luz sobre la línea activa, cursor con halo y estela luminosa en el acento del tema, e insignias de lenguaje y estado `GENERANDO`.
- Explorador de carpetas refinado en `ProjectExplorerWindow.qml`, `ViewerMotion.qml` y `WorkStatusNote.qml`: cabecera con gema activa e indicador `EN VIVO` / contador de visores, guías verticales de jerarquía, iconos vectoriales de carpeta y puntos de color por lenguaje, píldoras coloreadas para cambios (`Creado`, `Nuevo`, `Modificado`), entrada con escala cristalina e indicador de actividad con halo pulsante.
- Verificación completa con 295 pruebas Python, `qmllint` y los 12 escenarios reales de Qt/Quickshell (`./scripts/smoke.sh`).

## [0.24.0] — 2026-11-22

Esta versión sincroniza en tiempo real el diseño Matte Transparent Glassmorphism de Agent Shell y del generador Gema UI Kit (`App`) con el tema Gema de Hyprland (`~/.config/gema/preferences.json`), unificando superficies translúcidas, reflejos de agua, tipografía en relieve y micro-interacciones.

- Nuevo singleton `ui/components/shared/GemaTheme.qml` (y módulo `qmldir`): observa en vivo `~/.config/gema/preferences.json` (`FileView` con `watchChanges: true`) y sincroniza el acento (`accent`), nombre y símbolo de la gema activa (`gemName`, `gemSymbol`), colores de texto y sombras sin reiniciar la aplicación.
- Acabado Matte Transparent Glassmorphism unificado (`MattePanel.qml`, `GlassPanel.qml`, `WaterReflection.qml`, `ActionButton.qml`, `GlassComboBox.qml`, `GlassDialog.qml`): película de vidrio translúcido (`#54141c26` → `#680c121a`) con resplandor radial central teñido por la gema activa, bisel interior luminoso (*Hairline Frosted Rim*), cápsulas 3D en botones y tarjetas, y desenfoque de fondo con color vivo (`saturation: -0.35`, `blurMax: 36`).
- Interfaz interactiva y tipografía con relieve (`Text.Raised`): pestañas con iconos facetados (`◈ Chat`, `❖ Work`, `▲ App`), insignia de la gema activa, tarjetas de sugerencia interactivas en `ConversationPane.qml`, encabezados enriquecidos en `WorkProjects.qml` y `ChatSidebar.qml`, y actualización de las plantillas generadas en `backend/harness/work/gema_kit.py`.
- Verificación completa con 296 pruebas Python, `qmllint` y los 12 escenarios reales de Qt/Quickshell (`./scripts/smoke.sh`).

## [0.23.0] — 2026-11-22

Esta versión refuerza la protección de salidas de herramientas con fusibles en vivo contra inundaciones y volcados binarios, limpieza de barras de progreso, deduplicación de líneas repetidas y rescate inteligente de diagnósticos en el centro omitido.

- Fusibles en vivo en `ShellExecutor` (`backend/harness/tools/shell.py`): detiene de inmediato procesos desbocados que superan `MAX_STREAM_BYTES` (`2 MiB`) o producen volcados binarios con bytes NUL (`MAX_BINARY_NULS = 64`), sin esperar al timeout completo de la orden.
- Limpieza semántica en `compact_result` (`backend/harness/tools/output.py`): colapsa barras de progreso con `\r` (`collapse_carriage_returns`), deduplica bloques de líneas repetidas consecutivas (`collapse_repeated_lines`) y recorta líneas individuales gigantes como JS/JSON minificado (`clip_long_lines`).
- Rescate de diagnósticos en la parte omitida (`extract_middle_diagnostics` y cosecha en streaming de `BoundedOutput`): cuando una salida grande se trunca, extrae bloques con `Traceback`, `FAIL:`, `ERROR:`, `*Error:` o `AssertionError` del centro descartado y los incluye dentro del presupuesto de caracteres del modelo.
- Verificación con 295 pruebas Python aprobadas (`test_shell.py` y `test_patch_and_files.py`).

## [0.22.0] — 2026-11-22

Esta versión añade el espacio `App` (Gema UI Kit) junto a `Chat` y `Work`, permitiendo crear, probar e iniciar aplicaciones de escritorio nativas con diseño Dark Glassmorphism para Quickshell y motores Python o Rust.

- Nueva pestaña `App` en `WorkspaceSwitcher.qml`, `WorkProjects.qml` y `ProjectDialog.qml` con selección de motor (`Quickshell + Python` o `Quickshell + Rust`) y separación de historial, proyectos y aplicaciones en SQLite (`kind` y `engine` en `projects`).
- Nuevo generador `backend/harness/work/gema_kit.py`: crea automáticamente la estructura Glassmorphism de Gema UI Kit (`shell.qml`, `ui/AppBridge.qml`, `ui/AppWindow.qml`, `GlassPanel`, `MattePanel`, `WaterReflection`, `ActionButton`, `GlassDialog`, `GlassComboBox`, puente IPC JSON-Lines v2 sobre `stdin`/`stdout`, `scripts/check.sh` y `scripts/run.sh`).
- Botones `Probar` (`app.test`, validación rápida con `qmllint` y chequeo IPC del motor) e `Iniciar`/`Detener` en la cabecera de `App` en `ChatWindow.qml`, con arranque directo sin inferencia cuando `scripts/run.sh` está presente.
- Instrucciones de sistema `GEMA_UI_INSTRUCTIONS` inyectadas automáticamente en el área `App` para guiar a la IA en el diseño Glassmorphism de Gema UI Kit.

## [0.21.0] — 2026-11-22

Esta versión añade integración nativa para Arch Linux y el estándar XDG Base Directory, con migración automática no destructiva desde `.runtime/`, empaquetado oficial (`PKGBUILD`), lanzador de escritorio y servicio `systemd --user`.

- Nuevo módulo `backend/harness/core/paths.py`: separa datos (`$XDG_DATA_HOME/agent-shell`), configuración (`$XDG_CONFIG_HOME/agent-shell/limits.json`, segura para dotfiles) y sesión privada OAuth (`$XDG_STATE_HOME/agent-shell/session`, `0700`/`0600`), conservando precedencia total de flags CLI y variables `AGENT_SHELL_*`.
- Migración automática, atómica e idempotente (`.migrated-from-runtime`) desde `.runtime/` usando `sqlite3.backup()` para WAL y copias `0600` sin seguir enlaces simbólicos, preservando `.runtime/` como respaldo.
- `get_version()` soporta lectura desde metadatos del paquete instalado (`importlib.metadata`) además de `pyproject.toml`; `pyproject.toml` amplía compatibilidad a `Pillow>=11,<14` (Arch Linux `python-pillow 13.0`); `AgentBridge.qml` y `run.sh` respetan `AGENT_SHELL_WORKSPACE`.
- Empaquetado Arch Linux en `packaging/arch/` (`PKGBUILD`, `/usr/bin/agent-shell`, `agent-shell.desktop`, `agent-shell.svg`, `agent-shell.service`), instalador de usuario sin `root` (`scripts/install-user.sh`) y guía `docs/guides/arch-linux.md`.
- Verificación con `desktop-file-validate`, `systemd-analyze --user verify`, 292 pruebas Python, `qmllint` y 12 escenarios Qt/Quickshell.

## [0.20.0] — 2026-11-22

Esta versión migra el almacenamiento local de conversaciones, métricas y proyectos a SQLite en modo WAL con un almacén de blobs binarios deduplicados por SHA-256, eliminando lecturas completas de historial en listados y métricas y convirtiendo el borrado de proyectos en una sola transacción ACID.

- Nuevo módulo `backend/harness/core/storage.py`: `StorageDB` en SQLite (`journal_mode = WAL`, `foreign_keys = ON`, `busy_timeout = 5000`, permisos `0600`, rechazo de enlaces simbólicos) y `BlobStore` content-addressed por SHA-256 (`blobs/`, permisos `0600`, verificación de integridad al leer).
- `HistoryStore` indexado en SQLite (`chats`, `turn_performance`, `chat_blobs`): `list()` y `performance(limit)` consultan índices directamente sin abrir historiales completos; las imágenes base64 se externalizan y deduplican en `blobs/` y los blobs huérfanos se limpian tras confirmar el `COMMIT`.
- `ProjectStore` sobre SQLite compartiendo base `agent-shell.db` con `HistoryStore`: `_delete_project` elimina el proyecto, todos sus chats de Work, métricas y referencias de blobs en una única transacción atómica (`ROLLBACK` completo ante fallo).
- Migración automática no destructiva desde archivos `*.json` y `projects/*.json` heredados (con copia de respaldo en `.migrated-json/`), conservando intactos archivos dañados y enlaces simbólicos; `benchmarks/runner.py` (`audit_history`) lee `agent-shell.db` en modo solo lectura con fallback a JSON.
- Verificación con 288 pruebas Python, `qmllint` y 12 escenarios Qt/Quickshell sin dependencias nuevas.

## [0.19.0] — 2026-11-22

Esta versión añade un sistema configurable y persistente de límites de tokens desde la interfaz (`/limites`), perfiles predefinidos y un fusible inteligente de tokens facturables que no penaliza los aciertos de caché.

- Perfiles integrados (`ahorro` 40k, `equilibrado` 60k, `grande` 80k) y valores personalizados guardados atómicamente con permisos privados (`0600`) en `config/limits.json` (`LimitsStore`), respetando overrides por variables de entorno y sin interferir con el directorio del historial de conversaciones.
- Fusible de turno por tokens facturables (`max_turn_billable_tokens` / `AGENT_SHELL_MAX_TURN_BILLABLE_TOKENS`): contabiliza únicamente `entrada sin caché + salida`, permitiendo sesiones largas bien cacheadas y frenando loops costosos.
- Comando `/limites` y diálogo `TokenLimitsDialog.qml` con selección en un clic, edición fina de límites, contador de compactaciones del chat activo y validación local.
- Nuevas extensiones compatibles de NDJSON v2 (`limits.configure`, `limits.state`, `limits.rejected`) e indicador de contexto en `MessageComposer.qml` con tooltip de umbral/compactaciones y resalte al superar el 80 % del umbral.
- Verificación con 284 pruebas Python, `qmllint` y 12 escenarios Qt/Quickshell.

## [0.18.0] — 2026-11-22

Esta versión incorpora compactación inteligente de contexto con límite de 3 compactaciones por conversación, relevo automático a un chat nuevo limpio con lo esencial del software y contexto real de Git en Work.

- Contexto Git real en el bootstrap de Work (`git_software_context`): rama actual, últimos 8 commits (`git log`) y `git status --short` filtrando secretos `.env*`, disponible desde el primer turno y durante compactaciones y relevos.
- Compactación inteligente (`/compact` y automática al superar `AGENT_SHELL_COMPACT_THRESHOLD_TOKENS`, 60 000 por defecto): resume el historial antiguo sin borrar mensajes visibles ni romper pares `function_call`/`function_call_output`, omitiendo imágenes base64 viejas y razonamiento cifrado.
- Límite de compactaciones (`AGENT_SHELL_MAX_COMPACTIONS`, 3 por defecto) con relevo automático (*handoff*): al superar el límite crea un chat nuevo limpio (`parent_chat_id`, `compaction_count: 0`) sembrado con bootstrap fresco, `git log` real y resumen filtrado de lo que realmente aporta al software, conservando intacto el chat anterior.
- Nuevas extensiones compatibles de NDJSON v2 (`chat.compact` y `chat.compacted`) y campos opcionales en el esquema 1 del historial (`compaction_count` y `parent_chat_id`).
- Verificación con 282 pruebas Python, `qmllint` y 12 escenarios Qt/Quickshell.

## [0.17.0] — 2026-11-22

Esta versión reduce el consumo real de tokens y viajes al modelo mediante herramientas nativas de archivo, ejecución en paralelo, afinidad de caché de prompts y bootstrap inicial de proyectos en Work, e incorpora la eliminación de cuentas guardadas desde la interfaz.

- Eliminación de cuentas registradas (`auth.remove`) con botón **Quitar** y diálogo de confirmación: intenta revocar el token remoto, borra el registro local conservando `host_id`, historiales y proyectos, evita etiquetas duplicadas y promueve automáticamente otra cuenta conectada cuando se quita la activa.
- Herramientas nativas dedicadas (`apply_patch`, `read_file` y `grep_files`) junto a `shell`, estrictamente confinadas al workspace (rechazan rutas absolutas, `..` y enlaces simbólicos): `apply_patch` valida y aplica cambios multi-archivo de forma atómica con seguimiento `inotify` en Work.
- Llamadas paralelas (`parallel_tool_calls: true`) con ejecución concurrente (`ThreadPoolExecutor`) para lotes de solo lectura (`read_file`/`grep_files`) preservando el orden de resultados, más limpieza de códigos ANSI (`strip_ansi`) en la vista compactada del modelo.
- Afinidad de caché de prompts mediante `prompt_cache_key` estable por conversación, cabecera `session_id` y propagación en memoria de `x-codex-turn-state`, más bootstrap estático inicial en Work (`AGENTS.md` + mapa acotado de archivos excluyendo secretos `.env` y enlaces simbólicos) para evitar viajes iniciales de exploración sin romper el prefijo cacheable.
- Validación en vivo con el benchmark (`opt3-bootstrap` frente a `baseline-v0.16` en `gpt-6.2-sol`): `-26,4 %` en tokens de salida, `-8,8 %` en entrada no cacheada, `+23,3 pp` en caché de pasos 2+ y `-13,2 %` de duración manteniendo `100 %` de tareas aprobadas; 276 pruebas Python, `qmllint` y 12 escenarios Qt.

## [0.16.0] — 2026-11-22

Esta versión añade una suite de benchmarks y auditoría de consumo para medir objetivamente el impacto de cada optimización del harness, y extiende la colocación automática de la tarjeta de uso en Hyprland tanto a Chat como a Work.

- Suite de benchmarks reproducibles (`benchmarks/` y `scripts/bench.sh`) con cinco tareas en repositorios temporales limpios, verificadores deterministas (pruebas ocultas y `unittest`), modo `--mock` offline y modo `--live` contra la cuenta real.
- Instrumentación transparente por solicitud HTTP (`input_tokens`, `cached_tokens`, `uncached_input_tokens`, `Cache Hit` en pasos 2+, `tools/call`, tamaño de payload y características enviadas) más lectura opcional de delta de cuota Codex antes y después sin guardar PII.
- Auditoría offline de `.runtime/chats` (`bench.sh audit`) y comparador A/B (`bench.sh compare`) con regla estricta de calidad: cualquier caída en tareas aprobadas se marca como regresión aunque baje el consumo.
- Colocación automática en Hyprland de la tarjeta de uso junto al chat desde el arranque, tanto en Chat como en Work, reprogramando la alineación al cambiar el título de ventana.
- Regresiones automáticas de las cinco tareas, verificadores, comparador A/B, auditoría y delta de cuota; conserva NDJSON v2 y el esquema 1 del historial.

## [0.15.0] — 2026-10-15

Esta versión hace más fiable el harness en tareas largas y reduce el contexto innecesario enviado al modelo. El agente puede continuar con límites configurables, espera a que los procesos de shell terminen realmente y conserva una salida compacta para decidir los siguientes pasos. También mejora la recuperación de respuestas transmitidas por streaming e incorpora una auditoría y una guía práctica para equilibrar continuidad, consumo y control.

- Continuación del agente con presupuestos configurables: 32 solicitudes y 64 herramientas por defecto, comandos de IA de hasta 300 segundos, umbral opcional de tokens reportados y detención ante fallos idénticos consecutivos.
- Continuación automática de comentarios intermedios; respuestas vacías y límites se informan sin presentar la tarea como completada. Resultados y cambios se conservan para continuar.
- Shell que espera al proceso aunque cierre stdout/stderr; captura de inicio y final de logs, resultados nuevos acotados para el modelo y supresión de eventos de salida sin cambios.
- Reconstrucción de respuestas finales parciales con los elementos completados del stream, conservación de razonamiento cifrado y cierre explícito del transporte antes de ejecutar herramientas.
- Auditoría de lógica/consumo y guía de prácticas para LLM con presupuestos, uso eficiente de shell, criterios de aceptación y medición sin confundir tokens con cuota del plan.
- Regresiones de procesos reales, continuidad, límites, recorte, recuperación del stream e integración Qt; compatibilidad con NDJSON v2 e historial de esquema 1.

## [0.14.1] — 2026-10-13

- Pruebas QML agrupadas en `tests/ui/` y guía de integración de terminal en `docs/`, con imports, scripts de comprobación y documentación actualizados.
- Interfaz agrupada por áreas en `ui/components/` y módulos JavaScript reunidos en `ui/js/`, con imports y documentación actualizados.
- Backend organizado en paquetes de cuenta, chat, núcleo, herramientas y Work, con imports, dobles de prueba y lectura de versión adaptados.
- Documentación agrupada por proyecto, diseño técnico y guías, con índice central y enlaces relativos actualizados.
- Pruebas Python agrupadas por área en `tests/backend/`, escenarios de interfaz en `tests/ui/` y dobles y ayudantes compartidos en `tests/support/`; descubrimiento por paquetes y rutas de prueba centralizadas.
- Verificación con 230 pruebas Python, revisión QML, 12 escenarios de interfaz y 33 enlaces internos; conserva NDJSON v2 y el esquema 1 del historial.

## [0.14.0] — 2026-10-12

- Uso del plan abierto al iniciar, con consulta automática al estar disponible la cuenta; explorador y visores conservados y actualizados entre Work y Chat, contexto de proyecto independiente, retorno sin perder carpetas/archivos e invalidación al cambiar o eliminar el proyecto.
- Distribución simétrica de Work en Hyprland: tres columnas iguales, chat centrado con uso encima, dos ventanas izquierdas de igual altura, márgenes y separaciones uniformes; adaptación al área útil y altura real de las cuotas, con reapertura y libertad de movimiento posterior.
- El explorador y los dos visores de texto se colocan en el escritorio virtual y monitor de la ventana principal del chat en Hyprland, también al reabrirlos y durante aperturas automáticas de la IA; traslado silencioso sin cambiar el escritorio activo.
- Selector `/modelos` por familias, modelos y esfuerzo de razonamiento en la misma franja compacta; navegación con flechas laterales, compatibilidad por modelo, Auto, envío real del esfuerzo a Responses y detección de Work, y persistencia por conversación sin crear mensajes de chat.
- Inicio rápido por proyecto: lectura previa acotada para la detección, guardado persistente del comando y siguientes ejecuciones locales sin IA; comprobación de configuración, recuperación de un inicio fallido y uso sin conexión cuando la orden guardada sigue vigente.
- Botón Ejecutar/Detener en Work, sustituyendo Explorador y Abrir carpeta: la IA detecta el inicio del proyecto mediante archivos reales en una tarea interna, sin mensajes ni historial de chat; programa persistente, estado y salida reciente discretos, conversación simultánea, cancelación y aislamiento por proyecto.
- Corrección del entorno de shell: conserva la sesión Wayland/X11, autorización X11, D-Bus y configuración del escritorio para abrir aplicaciones gráficas desde comandos locales o de la IA, sin heredar variables arbitrarias del backend; pruebas de Wayland, X11 y ausencia de sesión gráfica.
- Validación con 230 pruebas del backend, revisión QML y 12 escenarios de interfaz; disposición de cinco ventanas, apertura inicial de uso, conservación entre Chat/Work y reapertura comprobadas en Hyprland real con un backend de prueba, sin inferencia ni OAuth reales.

## [0.13.0] — 2026-10-12

- Uso del plan en tarjeta flotante compacta: sólo límites, porcentajes restantes, barras finas y renovación; 320 píxeles de ancho y altura adaptativa, sin cabecera, botones ni datos secundarios, arrastre desde la tarjeta, Esc/F5, actualización sólo visible y reapertura, con chat simultáneo y conservación entre Chat/Work.
- Consulta nativa de cuotas mediante Codex: RPC acotado sin inferencia, comprobación de correo e invalidación al cambiar de cuenta, porcentajes comparables con la web y fecha local en tooltip; pruebas de extremos, datos desconocidos, aislamiento, interacción y ciclo de vida, además de consulta real verificada.
- Un único botón de envío cambia a Detener durante respuestas y comandos; permite cancelar incluso con el editor vacío y recupera Enviar al finalizar, conservando el borrador.
- Eliminación de proyectos desde Work con papelera discreta y confirmación: retira registro, conversaciones, mediciones y borradores, conservando la carpeta y los archivos locales; valida el aislamiento, los errores y la persistencia después de reiniciar.
- Escritura progresiva del código en los visores de Work, con cursor, duración adaptativa y seguimiento que respeta la lectura; anima contenido real ya recibido incluso después de un guardado atómico, sin retrasar comandos.
- Actualizaciones sucesivas sobre un único destino, conservación de prefijo/sufijo intactos, soporte de Unicode y finalización de la última vista al cancelar, cerrar o eliminar; apertura manual inmediata.
- Nuevo escenario gráfico de guardado real por shell, animación posterior al comando, modificaciones en ráfaga, cursor, Unicode, sondeo, cancelación, 128 KiB, seguimiento y reapertura.

## [0.12.0] — 2026-10-12

- Animaciones suaves en Work: entrada de ventanas, aparición y retirada de carpetas/archivos, recolocación de filas, giro de flechas y transición al rotar los visores.
- Resaltado localizado del intervalo de código modificado con una barra lateral tenue, adaptable al ajuste de línea y tamaño; punto de actividad animado sólo durante trabajo visible, conservando el texto real y el cierre inmediato.
- Árbol actualizado por ruta sin recrear delegados durante el sondeo; ampliación de la prueba gráfica para comprobar identidad de filas, entradas, ventanas, cambios de archivo y ubicación real de las líneas resaltadas.
- Seguimiento automático del trabajo de la IA en Work: árbol al ejecutar shell, carpetas expandidas y dos visores que siguen los archivos creados o modificados, con rotación automática, instantáneas reales y resaltado animado.
- Observación inotify acotada durante cada comando, con eventos compatibles `work.activity` y `work.changed`, eliminación y renombrado, estados de ejecución y cancelación, aislamiento por turno/proyecto y exclusión del historial privado; sin añadir las vistas al contexto del modelo.
- Pruebas con procesos reales y HTTP local para escritura intermedia, apertura automática, animación, rotación, cierres, reapertura y cancelación.
- Colocación de visores por identidad de ventana aunque la IA rote el archivo antes del mapeo en Wayland; comprobación de la apertura automática y la disposición real en Hyprland.
- Verificación con 167 pruebas del motor, revisión QML y ocho escenarios de interfaz; herramientas y cambios de archivos reales con servicio HTTP local de prueba.
- Visores de carpetas y texto más compactos, sin títulos grandes ni botones Actualizar/Cerrar; ruta con información completa al pasar el puntero, arrastre desde la cabecera y cierre con Esc o el compositor.
- Información discreta de actualización automática y entradas visibles en el árbol; solo lectura, número de líneas y aviso de vista parcial en los archivos, conservando el acabado mate y la actualización cada 1,5 segundos.

## [0.11.1] — 2026-10-11

- Corrección de la reapertura del explorador y los dos visores tras cerrar desde el compositor: sincronización de la intención de visibilidad, limpieza de solicitudes pendientes y regresión gráfica de cierre nativo y nueva lectura.
- Disposición inicial del explorador según la captura de referencia: carpetas arriba a la izquierda, visor 1 alto a la derecha y visor 2 abajo a la izquierda, con tamaños y posiciones adaptados al área útil del monitor y restaurados al reabrir.
- Compatibilidad de la colocación automática con los dispatchers Lua de Hyprland 0.55+; conservación de las órdenes anteriores y selección aislada por proceso y dirección de ventana.
- Verificación con 159 pruebas, revisión QML, siete escenarios de interfaz y apertura, cierre nativo y reapertura de las tres ventanas en Hyprland, comprobando también sus tamaños y coordenadas reales.

## [0.11.0] — 2026-10-11

- Imágenes mediante Ctrl+V en Chat y Work, con miniatura discreta, botón para quitar, envío con o sin texto y recuperación desde el historial; adjuntos del borrador por área y descarte de respuestas tardías del portapapeles.
- Entradas multimodales de Responses con una imagen PNG/JPEG/WebP por mensaje, validada hasta 4 MiB y 16 megapíxeles; lectura binaria acotada mediante wl-paste o xclip, dependencia Pillow y ampliación compatible de NDJSON v2 hasta 8 MiB por línea.
- Pruebas de formato, límites, contexto, historial, reinicio, lectura del portapapeles y recorrido Qt de imágenes con datos y servidor HTTP locales de prueba.
- Validación completa con 157 pruebas del motor, revisión QML y siete escenarios de interfaz; incluye el explorador, la colocación de visores y la integración de imágenes, sin consumir una cuenta ni modificar el portapapeles del usuario.

- Colocación inicial de los visores en Hyprland adaptada al monitor y sus zonas reservadas: visor 1 abajo a la izquierda y visor 2 alto a la derecha; reapertura restaura la disposición sin impedir mover o redimensionar después.
- Hasta dos visores de texto simultáneos, numerados e independientes, con identificadores de lectura únicos; archivos ya abiertos no se duplican, un visor cerrado se reutiliza y el tercer archivo muestra un aviso sin sustituir los demás. Prueba gráfica del límite, lectura aislada y limpieza de los dos visores.

- Separación del árbol de carpetas y el visor de archivos en dos ventanas mate independientes; selección de archivos abre o reutiliza el visor, con sondeo y cierre propios y limpieza al cambiar de espacio. Prueba gráfica de actualización con el árbol cerrado, reapertura y descarte de respuestas tardías.

- Fondo glassmorphism mate del explorador, con transparencia, reflejos suaves y desenfoque nativo en compositores compatibles; vista previa y selección integradas en el acabado monocromático.

- Explorador independiente en Work: árbol perezoso de carpetas, sondeo cada 1,5 segundos y marcas de archivos nuevos o modificados durante la apertura.
- Vista previa UTF-8 de solo lectura, con límite de 128 KiB; rutas confinadas al proyecto, rechazo de enlaces simbólicos y archivos especiales, y exclusión de carpetas pesadas o internas.
- Eventos compatibles `explorer.list`, `explorer.file` y `explorer.error` en NDJSON v2; lectura sin IA, independiente de los turnos, con correlación de solicitudes y limpieza al cambiar de espacio.
- Pruebas del backend y escenario gráfico para apertura, expansión, texto, cambios y cierre al cambiar de área.

## [0.10.0] — 2026-10-11

- Selector Chat | Work centrado arriba de la ventana; conversación general y trabajo sobre proyectos con el mismo diseño mate.
- Proyectos de Work vinculados a carpetas locales, con nombre, selector de carpeta, acceso al explorador y registro privado y atómico; cada proyecto conserva sus conversaciones y comandos.
- Historial y contexto separados por área y proyecto, restauración de la conversación y el borrador al cambiar durante la sesión, y conservación de los chats anteriores en Chat.
- Directorio de terminal propio para Chat y cada proyecto; instrucciones de Work para inspeccionar, implementar y verificar cambios, con terminal disponible en ambas áreas y cambios bloqueados mientras hay operaciones en curso.
- Ampliación compatible del protocolo v2 y del historial con esquema 1 para proyectos y áreas; pruebas de persistencia, aislamiento, cancelación y carpetas reales.
- Validación con 132 pruebas del motor, revisión QML y cinco escenarios gráficos; creación de dos proyectos, borradores, historial separado y shell en cada carpeta con servicio HTTP local de prueba.

## [0.9.0] — 2026-10-11

- Contexto junto a Enviar, con conteo exacto al pasar el cursor y acceso a los detalles; duración y velocidad permanecen bajo la respuesta, y la última medición se recupera al abrir el historial.
- Indicadores discretos de contexto en tokens de la última llamada y velocidad media en tok/s, basada en conteos reales y tiempos HTTP por solicitud; separación de consumo acumulado, razonamiento, caché y ejecución de terminal en Rendimiento, con datos desconocidos sin estimaciones.
- Instrucciones de la IA para confirmar brevemente el resultado de comandos simples sin duplicar la salida de las tarjetas de terminal, distinguiendo éxito, error, timeout e interrupción y conservando la interpretación en tareas de análisis.
- Tarjetas de terminal más discretas: comando en la cabecera, estado y duración real, directorio abreviado con ruta completa al pasar el cursor, vista ampliable de salidas largas y copia de la salida original; aclaración cuando sudo necesita entrada interactiva.
- Comando `/shell comando` para ejecutar directamente sin IA ni sesión de ChatGPT, con tarjetas de Terminal local, salida, estado, cancelación e historial; sin enviar resultados al contexto del modelo ni crear mediciones de IA.
- Barras de desplazamiento ocultas sin perder navegación por rueda, gestos ni acceso al último mensaje.
- Terminal siempre disponible como función principal: la IA la usa según la tarea y todos los comandos se ejecutan automáticamente sin confirmación; el panel Terminal configura el directorio y Detener cancela los procesos.
- Protocolo NDJSON v2: eliminación de decisiones y eventos de aprobación; conservación de conversaciones anteriores y resultados de herramientas.
- Cabecera del chat eliminada para dar más espacio a la conversación.
- Estado de la respuesta junto al modelo en el editor, con texto completo al pasar el cursor; eliminación del pie separado y de la indicación Enter / Shift+Enter.
- Conversación más compacta sin avatares repetidos, separación más contenida y burbujas ajustadas al texto del usuario sin saltos de línea innecesarios; respuestas con Markdown, código, modelo utilizado, copia con confirmación y métricas discretas que abren sus detalles.
- Indicación mientras la IA prepara la respuesta y seguimiento del texto que respeta la lectura de mensajes anteriores, con acceso para volver al último mensaje.
- Barra lateral sin botón: aparece al acercar el puntero al borde izquierdo y se oculta al salir, con esperas breves para evitar aperturas accidentales; se superpone sin desplazar el chat en ventanas grandes y pequeñas y admite Ctrl+B y Esc para navegar con el teclado.
- 118 pruebas del motor, revisión QML y cuatro escenarios de interfaz con procesos locales reales y servicio HTTP de prueba; validación de contexto, velocidad en tokens, cancelación, historial y navegación sin desplazamientos.

## [0.8.0] — 2026-10-11

- Botón «Usar otra cuenta» con registro OAuth separado, selector de cuentas guardadas y cierre de sesión por cuenta; conservación del host, registros anteriores y conversaciones.
- Validación de la nueva identidad antes de activar la cuenta, compatibilidad con sesiones anteriores y pruebas de fallos, cancelación, cambio de cuenta y controles Qt.
- Comandos locales `/ayuda`, `/nuevo`, `/historial`, `/modelos`, `/terminal` y `/detener`, sin enviarlos al modelo ni crear mensajes o mediciones.
- Sugerencias compactas a la izquierda de Enviar, en el espacio del antiguo selector de modelos y con altura fija para no desplazar el chat; flechas izquierda/derecha para elegir, Enter para ejecutar, Tab para completar y Esc para ocultar.
- Editor más minimalista sin selector de modelos: sólo `/modelos` completo muestra y filtra los modelos dentro del prompt; los prefijos como `/mode` sugieren completar el comando. Selección mediante teclado o clic.
- Nombre del modelo activo como etiqueta discreta a la izquierda de Enviar, con identificador y recordatorio de `/modelos` al pasar el cursor; comparte espacio con las sugerencias sin desplazar el chat.
- Validación de disponibilidad y argumentos con conservación de borradores; editor disponible sin sesión y durante respuestas para usar comandos locales.
- Prueba Qt con sugerencias compactas, activación al completar `/modelos`, filtros, teclado, paneles, cancelación, validación, uso sin sesión y envío normal.
- 103 pruebas, revisión QML y dos escenarios Qt con servicio local de prueba; comprobación de altura y posición estables y actualización de la etiqueta del modelo. Inicio de sesión real con otra cuenta confirmado por el usuario.

## [0.7.0] — 2026-10-11

- Integración de shell local mediante llamadas estructuradas de Responses, con activación y directorio desde el panel lateral, confirmación por comando y tarjetas de salida.
- Ejecución secuencial con timeout, salida limitada, entorno mínimo y cancelación del grupo de procesos; recuperación del historial sin reejecutar llamadas.
- Contexto de herramientas persistente y métricas que separan ejecución y espera de confirmación de las respuestas de chat.
- Compatibilidad con streams que entregan las llamadas en `response.output_item.done` y omiten los elementos en el resumen final.
- 91 pruebas, revisión QML y comprobaciones gráficas con software y OpenGL; ciclo real con ChatGPT, ejecución aprobada de `pwd` y continuación desde el resultado.

## [0.6.0] — 2026-10-11

- Interfaz en blanco, negro y grises, incluidos controles, estados, bordes de foco y selección de texto.
- Vidrio mate uniforme y más marcado en el fondo principal, panel lateral, Historial, Cuenta, Rendimiento y diálogos; mayor desenfoque del chat detrás de los paneles superpuestos.
- Reflejos suaves de agua dibujados con Qt, recortados a los bordes del vidrio y sin animación continua; fondo principal con un 44–48 % de opacidad.
- Accesos a nuevo chat, historial, rendimiento y cuenta concentrados en el panel lateral; cabecera principal sin botones duplicados.
- Papelera con confirmación en el panel lateral y el historial; borrado local de mensajes y mediciones, también sin sesión. Borrar el chat abierto prepara uno nuevo; un fallo conserva el chat.
- 66 pruebas, revisión QML e integración Qt con borrado; comprobación gráfica de la confirmación y los paneles con software y OpenGL.

## [0.5.0] — 2026-10-11

- Interfaz de vidrio transparente con tinte ligero, bordes de un píxel y reflejos suaves; fondo principal con un 25–32 % de opacidad.
- Desenfoque nativo del fondo en compositores compatibles con Quickshell; botones, selectores, diálogos e historial con el mismo acabado.
- Navegación lateral con chats y acceso a la cuenta, cabecera de conversación y editor con modelo y envío integrados; barra compacta en ventanas pequeñas.
- Mensajes propios diferenciados, bienvenida con sugerencias editables y más espacio para la conversación.
- Botón para ocultar y mostrar la barra lateral, con navegación accesible al ocultarla y panel superpuesto en ventanas pequeñas.
- 58 pruebas, revisión QML e integración Qt; comprobación de sugerencias, envío, cuenta, selección de modelo y apertura/cierre de la barra en escritorio y vista compacta con servicio local de prueba.

## [0.4.0] — 2026-10-11

- Métricas por respuesta: primer texto, duración, velocidad de caracteres y tiempos de preparación, sesión, HTTP y presentación Qt.
- Historial de las últimas 200 mediciones y comparación por modelo con mediana y p95; fallos y cancelaciones separados.
- Conteos reales de tokens cuando OpenAI los entrega, conservación de métricas al reiniciar y compatibilidad con chats anteriores.
- 58 pruebas, revisión QML e integración Qt con reloj controlado, persistencia, cancelación, estadísticas y presentación; solicitud real completada con métricas del backend.

## [0.3.0] — 2026-10-11

- Conexión directa con ChatGPT sin Codex CLI ni App Server.
- Registro OAuth propio mediante Sign in with ChatGPT y permiso de uso del plan.
- Validación de identidad con PyJWT/cryptography, renovación serializada y sesión privada.
- Catálogo de modelos de la cuenta, selector, administración de uso y cierre de sesión.
- Contexto reconstruido desde mensajes locales, compatible con los chats de 0.2.0.
- HTTP/SSE cancelable, conservación del texto parcial y guardado agrupado del historial.
- Entorno Python local y script de instalación; opciones `--session-root` y `--model`.
- Retirada de `--codex-executable`, `--chat-root` y `AGENT_SHELL_CODEX`.
- Pruebas OAuth con claves RSA y HTTP/SSE local, además de la integración Qt sin Codex.
- Compatibilidad con respuestas SSE que omiten la cabecera `Content-Type`, como se observó en la ruta real.
- Tres pruebas de regresión para cabeceras de streaming ausentes o incompatibles y transmisiones sin evento de finalización.
- Autenticación real confirmada por el usuario y respuesta real verificada con el backend hasta `response.completed`.

## [0.2.0] — 2026-10-11

- Historial automático con un JSON por conversación en `.runtime/chats/`.
- Panel Historial con título, fecha, selección de chats y ubicación del directorio.
- Botón Abrir carpeta y ruta seleccionable para copiarla.
- Recuperación de mensajes incluso cuando Codex está desconectado.
- Threads persistentes y continuación mediante `thread/resume` de Codex.
- Guardado atómico, conservación de respuestas parciales y tolerancia a JSON dañados.
- Ubicación configurable con `AGENT_SHELL_HISTORY_DIR` y `--history-root`.
- Pruebas de recuperación tras reinicio, continuidad del thread y fallas de escritura.
- Ejecución única del shell y pruebas con historial aislado en directorios temporales.

## [0.1.0] — 2026-10-11

### Añadido

- Base de una aplicación de escritorio de IA con Quickshell y Qt Quick para Hyprland.
- Una ventana de chat sobre el App Server oficial de Codex, usando la cuenta ChatGPT
  de Codex CLI y su flujo OAuth administrado en el navegador.
- Respuestas progresivas reconciliadas por id, contexto entre mensajes, interrupción
  de respuestas y conversación nueva.
- Puente Python sin dependencias externas, transporte RPC concurrente y contrato
  de interfaz NDJSON v1 documentado.
- Manejo de errores, solicitudes inválidas, desconexión y cierre de procesos hijos.
- Versión centralizada en pyproject.toml, visible en el chat y consultable con --version.
- Documentación en español de visión, arquitectura, protocolo, contribución y SemVer.
- Diecisiete pruebas del motor e integración Qt con un doble explícito de App Server.

### Límites conocidos

- Autenticación e inferencia reales pendientes de comprobar en el escritorio.
  El entorno restringido de desarrollo impide iniciar App Server porque el directorio
  de Codex es de sólo lectura; las pruebas usan un doble sin credenciales.
- Conversaciones efímeras, sin recuperación de historial ni selector de modelos.
- Presentación de texto sin editor, terminal ni herramientas de trabajo sobre proyectos.
- Las ventanas para observar el trabajo del agente pertenecen a una etapa posterior.

[0.1.0]: docs/project/versioning.md

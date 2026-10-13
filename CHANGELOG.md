# Historial de cambios

Las versiones del proyecto siguen [SemVer 2.0.0](https://semver.org/lang/es/).
Cada versión identificada corresponde a una etiqueta Git anotada `vX.Y.Z`.

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

[0.1.0]: docs/versioning.md

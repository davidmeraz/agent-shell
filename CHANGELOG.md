# Historial de cambios

Las versiones del proyecto siguen [SemVer 2.0.0](https://semver.org/lang/es/).
Cada versión identificada corresponde a una etiqueta Git anotada `vX.Y.Z`.

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

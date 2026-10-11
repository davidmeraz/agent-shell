# Historial de cambios

Las versiones del proyecto siguen [SemVer 2.0.0](https://semver.org/lang/es/).
Cada versión identificada corresponde a una etiqueta Git anotada `vX.Y.Z`.

## Pendiente de publicar

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

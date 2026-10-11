# Historial de cambios

Las versiones del proyecto siguen [SemVer 2.0.0](https://semver.org/lang/es/).
Cada versión identificada corresponde a una etiqueta Git anotada `vX.Y.Z`.

## Pendiente de publicar

Sin cambios posteriores a la base inicial.

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

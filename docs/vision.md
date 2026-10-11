# Visión de Agent Shell

Crear una aplicación propia de IA para Linux con Quickshell y Qt, integrada en
el escritorio administrado por Hyprland. La aplicación administra su experiencia
de conversación y su conexión con ChatGPT sin requerir Codex CLI.

## Base de conversación

- Conectar una cuenta ChatGPT con sesión propia y permiso de uso del plan.
- Descubrir modelos disponibles y elegirlos desde la interfaz.
- Recibir texto progresivo, detener respuestas y crear chats.
- Guardar y recuperar conversaciones en archivos locales legibles.
- Mantener contexto desde esos mensajes, sin depender de threads de otro cliente.
- Mostrar cuenta, modelo, conexión y uso del plan con claridad.

## Trabajo visual sobre proyectos

La propuesta incluye observar el trabajo del agente en el escritorio: archivos,
carpetas, código y acciones visibles en ventanas de Hyprland. Esa experiencia se
construirá sobre el chat después de definir herramientas, edición y permisos.

La base ahora incluye conversación y una herramienta de shell siempre disponible,
con ejecución automática, directorio elegido y resultados visibles. No incluye todavía una
terminal interactiva ni herramientas dedicadas de edición de archivos.
Las pruebas automatizadas usan OAuth firmado de prueba y un
servicio HTTP local; el acceso con una cuenta real se valida en el escritorio.

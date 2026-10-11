# Visión de Agent Shell

Crear una aplicación de escritorio de IA para Linux, inspirada en la experiencia
de las aplicaciones de Codex y ChatGPT, con una interfaz propia en Quickshell y Qt.
Hyprland administra sus ventanas como parte del escritorio del usuario.

## Primera etapa: conversar con tu cuenta

La base inicial se concentra en una ventana de chat conectada al motor de Codex:

- Reutilizar la cuenta de ChatGPT autenticada en Codex CLI.
- Iniciar sesión desde la aplicación mediante el flujo oficial de Codex.
- Enviar mensajes, recibir texto progresivo y mantener contexto entre turnos.
- Detener respuestas e iniciar conversaciones nuevas.
- Mostrar con claridad cuenta, conexión, modelo y estado de la respuesta.

El cliente utiliza Codex App Server; Codex administra autenticación e inferencia.
Quickshell y Qt presentan la experiencia del usuario. Esta integración crea
conversaciones propias, sin importar el historial de otras aplicaciones.

## Evolución que se diseñará después

La propuesta original incluye observar el trabajo real del agente en el escritorio:
archivos, carpetas, código y acciones que aparezcan en ventanas de Hyprland. Esa
experiencia se construirá sobre el chat, después de acordar el flujo de herramientas,
edición de proyectos y permisos con el usuario.

La primera versión establece la arquitectura del chat y su conexión con Codex.
Las pruebas automatizadas usan un App Server simulado; la autenticación y una
respuesta real deben validarse en la sesión de escritorio del usuario.

# Agent Shell

Cliente de chat para **Codex**, construido con **Quickshell y Qt Quick** para Linux
con Hyprland. Reutiliza la cuenta de ChatGPT iniciada en Codex CLI y muestra la
respuesta conforme llega. El motor es el App Server oficial de Codex.

**Base inicial: 0.1.0**, identificada con la etiqueta Git local `v0.1.0`.

La visión es construir una aplicación de escritorio propia, inspirada en la
experiencia de Codex y ChatGPT, usando Quickshell y Qt. Esta primera etapa se
concentra en el chat autenticado; el trabajo visual sobre proyectos se diseñará
después. Consulta la [visión del proyecto](docs/vision.md).

## Ejecutar

Requisitos: Python 3.11+, Quickshell 0.3.x con Qt Quick Controls y Layouts, Codex CLI
con `app-server --stdio` y una sesión gráfica. La interfaz de la CLI se inspeccionó
con Codex 0.162.1. Python no requiere paquetes externos.

```bash
cd /home/dav3e/Dev/quickshell/agent-shell
./scripts/run.sh
```

Al arrancar, el chat consulta la sesión de Codex. Si ya has iniciado sesión con
ChatGPT, puedes enviar un mensaje inmediatamente. Usa **Enter** para enviar y
**Shift+Enter** para un salto de línea. **Detener** interrumpe la respuesta y
**Nuevo chat** inicia otra conversación. Puedes seleccionar y copiar los mensajes.

Se usa el proveedor OpenAI con la cuenta ChatGPT; el modelo lo decide la configuración
efectiva de Codex. Esta versión no incluye selector de modelos. El contenido se
presenta como texto, incluido el código.

## Autenticación con tu cuenta

El estado se consulta a través de `account/read` del App Server, sin abrir ni copiar
credenciales. El botón **Iniciar sesión** solicita el flujo oficial de Codex y abre
la URL de autorización en el navegador. Codex recibe la confirmación local y guarda
la sesión en su propio almacén. El botón **Actualizar** vuelve a consultar la cuenta
si has iniciado sesión desde otra terminal.

También puedes preparar la sesión antes de abrir el chat:

```bash
codex login
codex login status
```

Si el callback del navegador no funciona en tu entorno, utiliza el flujo de
código de dispositivo de la CLI y vuelve a abrir el chat:

```bash
codex login --device-auth
```

Se acepta una cuenta de tipo ChatGPT. Si la CLI está configurada con una API key,
el chat pide iniciar sesión con ChatGPT. Disponibilidad, límites y acceso a modelos
los determina tu cuenta y Codex. Las conversaciones de esta aplicación son nuevas;
no se importa el historial de ChatGPT ni se sincronizan chats entre aplicaciones.
No hay botón de cierre de sesión porque la sesión se comparte con la CLI.

## Alcance actual

Una sola ventana para conversar, con historial durante la sesión. Los threads son
`ephemeral`: no hay recuperación de conversaciones al reiniciar. El contexto se
mantiene en el mismo thread mientras el chat esté abierto.

Los chats usan `.runtime/chat/` como directorio de contexto, política `read-only`, herramientas
shell desactivadas e instrucciones de conversación. No hay herramientas propias
para crear proyectos, terminal, adjuntos ni edición de archivos. No se modifica la
configuración de Hyprland ni se selecciona una API key.

## Estructura

```text
shell.qml                 Abre la ventana del chat
ui/AgentBridge.qml        Estado de cuenta, mensajes y eventos
ui/ChatWindow.qml         Interfaz del chat y autenticación
ui/components/            Controles visuales compartidos
backend/main.py           Entrada y ciclo de vida del puente
backend/harness/codex.py   Cliente RPC del App Server oficial
backend/harness/server.py Traducción de cuenta, threads y turnos
backend/harness/events.py Eventos de la interfaz NDJSON v1
backend/harness/version.py Versión centralizada en pyproject.toml
tests/                    Pruebas y doble de App Server
smoke.qml                 Integración Qt para las pruebas
scripts/                  Lanzamiento y comprobaciones
docs/                     Arquitectura, protocolo y versiones
```

## Comprobaciones

```bash
./scripts/check.sh
./scripts/smoke.sh
python3 backend/main.py --version
```

Las pruebas usan un doble de App Server explícito, sin red ni consumo de tu cuenta.
La integración arranca Qt offscreen, atraviesa Python y un proceso simulado de Codex,
y comprueba cuenta, streaming, cancelación y nuevo chat. No prueba una respuesta
real del modelo ni completa OAuth. En entornos restringidos se tolera únicamente
el diagnóstico del socket IPC auxiliar de Quickshell bloqueado.

Para comprobar el App Server real, sin abrir el navegador ni pedir una respuesta:

```bash
python3 backend/main.py < /dev/null
```

Debe publicar `backend.ready` y `auth.state`, y salir. Este comando muestra datos
básicos de cuenta (correo y plan), nunca tokens. Si publica `backend.disconnected`,
comprueba `codex app-server --stdio < /dev/null` y los permisos de tu directorio de
Codex. El entorno restringido de desarrollo permitió consultar `codex login status`,
pero impidió arrancar App Server porque el directorio de Codex era de sólo lectura.
La interacción real con tu cuenta debe comprobarse desde tu sesión de escritorio.

`AGENT_SHELL_CODEX` permite indicar la ruta del ejecutable si no está en PATH. Sólo
el script de pruebas la cambia a `tests/fake_codex.py`; el lanzador normal usa Codex.

Consulta [arquitectura](docs/architecture.md), [protocolo](docs/protocol.md),
[versiones](docs/versioning.md), [historial](CHANGELOG.md) y
[contribución](CONTRIBUTING.md).

Referencias oficiales: [Codex App Server](https://learn.chatgpt.com/docs/app-server),
[autenticación](https://learn.chatgpt.com/docs/auth) y
[configuración](https://learn.chatgpt.com/docs/config-file/config-reference).

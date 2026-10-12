# Versionado Semántico

Agent Shell sigue [SemVer 2.0.0](https://semver.org/lang/es/) y comienza en **0.1.0**
con el chat de Codex construido en Quickshell y Qt. La etiqueta local `v0.1.0`
identifica el único commit inicial de esta base.
La última versión etiquetada es `0.10.0`, con áreas Chat y Work seleccionadas
desde el centro superior de la ventana. Work registra proyectos con carpetas
locales, conversaciones y contextos separados; el cambio de espacio conserva
la conversación abierta y el borrador durante la sesión. Los chats anteriores
siguen disponibles en Chat. Son ampliaciones compatibles de NDJSON v2 y del
historial con esquema 1, sin cambiar las etiquetas de versiones anteriores.
Conserva el chat compacto, Markdown y copia, la barra lateral al acercar el
puntero y el contexto junto a Enviar de `0.9.0`. La terminal está
siempre disponible para la IA y ejecuta automáticamente; `/shell comando`
ejecuta directamente sin IA ni sesión, con tarjetas de salida ampliables.
Las métricas separan contexto de la última llamada, consumo acumulado y velocidad
media en tokens por segundo, excluyendo el tiempo de terminal de esa media.
Conserva los comandos, selección mediante `/modelos` y cuentas de `0.8.0`, la
interfaz monocromática de vidrio mate y borrado de chats de `0.6.0`, y la sesión
propia y conexión directa con ChatGPT de `0.3.0`.
Usa NDJSON v2, que elimina decisiones y eventos de aprobación y la opción de
desactivar la terminal. Backend e interfaz deben actualizarse juntos. La ruptura
del protocolo durante `0.x` sigue la convención local de incrementar MENOR;
el historial conserva el esquema 1 y la compatibilidad con conversaciones anteriores.
El formato es `MAYOR.MENOR.PARCHE`. El prefijo `v` pertenece a la etiqueta Git,
por ejemplo `v0.1.0`; el número de versión de la aplicación es `0.1.0`.

## Fuente de la versión y contrato público

`project.version` en `pyproject.toml` es la única fuente de la versión de la
aplicación. Python la lee con `tomllib`, la expone mediante `--version` y la envía
en `backend.ready.data.app_version` para mostrarla en el chat.

El contrato público es el [protocolo NDJSON](protocol.md) y las opciones de la
línea de comandos documentadas en el README y en `backend/main.py --help`. Las
clases Python internas y la composición de QML no son una API pública estable.

El campo `version` de los eventos identifica el formato del protocolo (actualmente 2) y tiene
su propio ciclo de evolución. Una corrección de la aplicación puede cambiar de
`0.1.0` a `0.1.1` manteniendo el protocolo v1.

## Elegir la siguiente versión

| Situación | Ejemplo | Política del proyecto |
| --- | --- | --- |
| Correcciones compatibles y ajustes de documentación | `0.1.0` → `0.1.1` | Incrementar PARCHE |
| Nueva funcionalidad o cambios de diseño durante el desarrollo inicial | `0.1.0` → `0.2.0` | Incrementar MENOR y reiniciar PARCHE |
| Cambios incompatibles durante `0.x` | `0.2.0` → `0.3.0` | Por convención local, incrementar MENOR y documentar la ruptura |
| Primer contrato público estable | `0.x.y` → `1.0.0` | Declarar estabilidad del contrato |
| Nueva funcionalidad compatible a partir de `1.0.0` | `1.0.0` → `1.1.0` | Incrementar MENOR y reiniciar PARCHE |
| Ruptura del contrato estable | `1.1.0` → `2.0.0` | Incrementar MAYOR y reiniciar MENOR y PARCHE |

SemVer considera `0.x.y` desarrollo inicial: todavía no promete estabilidad del
contrato. La regla para rupturas durante `0.x` es una convención de este proyecto.
Las pruebas previas a una versión pueden usar `0.2.0-alpha.1`, `0.2.0-beta.1` o
`0.2.0-rc.1`. Los consumidores deben tratar esas versiones como prelanzamientos.

## Preparar una versión

No hace falta incrementar la versión en cada commit. Acumula las novedades en
`CHANGELOG.md`, bajo «Pendiente de publicar», y cambia el número cuando prepares
una versión identificable del proyecto.

1. Elige el incremento según la tabla y actualiza `project.version`.
2. Mueve los cambios pendientes a una sección con versión y fecha en `CHANGELOG.md`.
3. Actualiza documentación de opciones, eventos o compatibilidad si corresponde.
4. Ejecuta `./scripts/check.sh`, `./scripts/smoke.sh` y `python3 backend/main.py --version`.
5. Crea el commit de la versión y después una etiqueta anotada con el mismo número.

Ejemplo para una futura versión `0.2.0`, después de preparar y verificar los cambios:

```bash
git add pyproject.toml CHANGELOG.md docs backend ui
git commit -m "chore(release): preparar v0.2.0"
git tag -a v0.2.0 -m "Agent Shell v0.2.0: describir los cambios de esta versión"
```

Los tags se crean sobre commits ya verificados. Una versión publicada es inmutable:
sus correcciones reciben otra versión, sin mover su etiqueta ni reescribirla.
Las etiquetas locales no publican el proyecto automáticamente en ningún servicio.

## Consultar la versión

```bash
python3 backend/main.py --version
git tag --list 'v*' --sort=version:refname
git show v0.1.0 --no-patch
git describe --tags --always
```

`git describe` puede añadir distancia y hash si hay commits posteriores a un tag;
esa salida identifica el checkout y no reemplaza la versión de `pyproject.toml`.

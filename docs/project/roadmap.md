# Próximos pasos

[← Índice de documentación](../README.md)

La base actual conecta directamente con ChatGPT, con sesión propia, catálogo de
modelos, historial local y shell siempre disponible con ejecución automática. Incluye comandos
del chat, cambio entre cuentas guardadas y áreas Chat / Work con proyectos locales,
carpetas e historiales separados; el usuario confirmó un inicio de
sesión real con una cuenta nueva.

1. Ampliar la validación en el escritorio de renovación y conversación al cambiar
   de cuenta. Las pruebas automáticas no consumen cuentas.
2. Mejorar Markdown, bloques de código y lectura de mensajes durante streaming.
3. Mejorar la identificación y selección de espacios de trabajo en los registros
   de cuentas existentes.
4. Ampliar la evaluación de compactación y relevos automáticos en sesiones
   largas (ya implementados `/compact`, umbral configurable con `/limites`,
   límite de 3 compactaciones con chat de relevo y contexto Git en Work).
5. Ampliar herramientas y trabajo visual sobre proyectos: terminal interactiva,
   aislamiento y gestión de trabajos largos sobre `apply_patch`, `read_file`,
   `grep_files` y la shell ya integrada.
6. Evaluar continuidad y consumo con tareas reproducibles (`scripts/bench.sh`);
   medir resultado, llamadas, acierto de caché y tokens facturables.
7. Integración nativa en Arch Linux (rutas XDG, `PKGBUILD` y servicio
   `systemd --user`) y recuperación de red con idempotencia y presupuesto
   explícitos. Las lecturas completas del historial para listados y métricas
   ya fueron sustituidas por índices SQLite (WAL) + blobs deduplicados.

La [auditoría del harness](../technical/harness-audit.md) ordena los hallazgos y
explica los límites de lo ya implementado.

El chat ya no requiere Codex CLI. Las versiones anteriores permanecen en sus
etiquetas Git para consultar su arquitectura y decisiones históricas.

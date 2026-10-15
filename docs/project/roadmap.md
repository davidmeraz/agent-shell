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
4. Definir compactación del contexto para conversaciones largas: checkpoints
   verificables y conservación de pares de herramientas, imágenes necesarias e
   instrucciones. Ya se acotan resultados nuevos, pero no se resume el historial.
5. Ampliar herramientas y trabajo visual sobre proyectos: edición, terminal
   interactiva, aislamiento y gestión de trabajos largos sobre la shell ya integrada.
6. Evaluar continuidad y consumo con tareas reproducibles; medir resultado,
   llamadas y tokens reportados. El agente ya tiene presupuestos configurables,
   continuación de comentarios intermedios y detección de fallos repetidos.
7. Reducir lecturas completas del historial para listados y métricas, y diseñar
   recuperación de red con idempotencia y presupuesto explícitos.

La [auditoría del harness](../technical/harness-audit.md) ordena los hallazgos y
explica los límites de lo ya implementado.

El chat ya no requiere Codex CLI. Las versiones anteriores permanecen en sus
etiquetas Git para consultar su arquitectura y decisiones históricas.

# Contribuir

Mantén separadas interfaz Qt, contrato de eventos, servidor y transporte de Codex.
Documenta en español la intención, decisiones no obvias y límites de módulos públicos.

Ejecuta `./scripts/check.sh` y `./scripts/smoke.sh` antes de un commit. Los tests no
necesitan credenciales, no abren un navegador ni consumen la cuenta del usuario.
`tests/fake_codex.py` es sólo un doble de prueba seleccionado explícitamente.

Las verificaciones reales de OAuth y del modelo se realizan desde la sesión de
escritorio del usuario, usando su CLI. No copies auth.json ni implementes endpoints
privados para evadir el App Server. El login y los tokens pertenecen a Codex.

Si cambia el contrato Qt/Python, actualiza `docs/protocol.md` y ambas partes.
Una ruptura incrementa su versión de protocolo y sigue la política SemVer durante
`0.x`. Registra novedades en `CHANGELOG.md` y usa `project.version` como única fuente.

Los commits deben explicar comportamiento, motivos y verificación. Conserva etiquetas
publicadas y sigue [versionado](docs/versioning.md) para preparar nuevas entregas.
Nunca añadas credenciales, `.runtime/`, datos del usuario o registros privados.
La licencia de distribución sigue pendiente de decisión por el autor.

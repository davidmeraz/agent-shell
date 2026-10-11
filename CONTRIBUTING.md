# Contribuir

Mantén separadas interfaz Qt, contrato de eventos, servidor, autenticación,
HTTP e historial. Documenta en español la intención y los límites de los módulos.

Prepara el entorno con `./scripts/setup.sh`. Ejecuta `./scripts/check.sh` y
`./scripts/smoke.sh` antes de un commit. Las pruebas no abren autorización real
ni consumen una cuenta. `tests/fake_backend.py` inyecta cuenta de prueba y servicio
HTTP loopback en el backend real; el lanzamiento normal no usa ese doble.

El acceso real se comprueba desde el escritorio del usuario con la sesión propia
de Agent Shell. Usa el flujo oficial Sign in with ChatGPT para aplicaciones locales.
No copies credenciales de otros clientes ni implementes endpoints privados.
La sesión OAuth y sus tokens pertenecen a Agent Shell y se guardan aparte del chat.

Verifica state, nonce, PKCE, firma del ID token, identidad y permiso del plan.
Mantén la renovación serializada y las escrituras privadas y atómicas. Nunca
publiques tokens, URLs OAuth, datos privados o `.runtime/`.

Si cambia el contrato Qt/Python, actualiza `docs/protocol.md` y ambas partes.
Una ruptura de formato incrementa la versión del protocolo. Sigue SemVer durante
`0.x`, documenta cambios de opciones públicas y registra novedades en
`CHANGELOG.md`. `project.version` es la única fuente de versión.

Los commits deben explicar comportamiento y verificación. Conserva las etiquetas
publicadas; no las muevas ni reescribas. La licencia de distribución sigue pendiente
de decisión por el autor.

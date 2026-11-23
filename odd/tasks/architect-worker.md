# Architect/Worker Cross-Provider Pattern

Branch: `feat/architect-worker`
Delivery: `ask-on-risk` (default)
Test runner: `.venv/bin/python -m unittest discover -s tests -t .`

## Specs

- S1-S11: reemplazadas por S13-S17 (ver L6).
- S12: Botón "Unified" en la barra superior (topHeaderBar) del ChatWindow que activa/desactiva el modo unificado. Cuando está ON, el modelo activo recibe `DELEGATE_TOOL` y puede delegar a todos los proveedores. Cuando está OFF, funciona como antes sin delegate. El botón usa glassmorphism consistente con el resto del UI, se ilumina con accent color cuando está activo, y solo es visible cuando hay más de un proveedor disponible.
- S13: Obreros elegidos desde catálogos en vivo: modelo más nuevo por línea (fast/balanced/strong) y bucket de cuota. Los modelos tope y las líneas desconocidas nunca son obreros automáticos (`work/roster.py`).
- S14: `delegate(task, level, provider)` con esquema estricto válido. `level` elige el tier; la cuota restante desempata; un bucket con menos de 5% queda último; al agotarse uno se pasa al siguiente (`work/quota_router.py`).
- S15: ChatGPT, Claude y Gemini pueden ser arquitectos. Los CLI usan bloques ```delegate y continúan su misma sesión con los resultados (máximo 8 rondas).
- S16: Un obrero que falla, se agota, se interrumpe o no informa nunca se reporta como completado.
- S17: Los obreros Claude omiten memoria global, estilo y MCP, y conservan permisos, hooks y CLAUDE.md del proyecto.
- S18: "cuando se activa el modo unificado quiero saber que modelo es el arquitecto y cuales son los obreros puedes mejorar esto en la interfaz grafica"
- S19: "Quiero cuando este modo unificado muestre 3 mini ventanas del uso de los 3 provedores"

## Tasks

- T1 [S1,S2,S3,S4,S5] Foundation: WorkerResult + DELEGATE_TOOL + WORKER_INSTRUCTIONS + WorkerRouter con _chatgpt_worker — inline — DONE c847cd6
- T2 [S8] Integration: wire delegate en server.py (_describe_tool, _run_tool, AGENT_TOOLS, __init__) — inline — DONE c847cd6
- T3 [S6,S7] Cross-provider: _agy_worker + _claude_worker en WorkerRouter — inline — DONE c847cd6
- T4 [S9] QuotaAwareRouter: selección, detección de cuota, fallback — inline — DONE c847cd6
- T5 [S10] Worker events: emitir worker.* desde WorkerRouter — inline — DONE c847cd6
- T6 [S11] Tests: WorkerRouter + QuotaAwareRouter con fakes — inline — DONE c847cd6 (30 tests GREEN)
- T7 [S12] UI: Unified mode toggle — inline — DONE
- T8 [S13,S14,S15,S16,S17] Rediseño con modelos actuales — inline — DONE (sin commit)

- T9 [S18] Panel de equipo del modo unificado — inline — DONE (sin commit)
- T10 [S19] Tres ventanas de uso por proveedor — inline — DONE (sin commit)

## Log

- L1: "Puedes implementar todo esta arquitectura en mi proyecto" — usuario pide implementar el diseño completo del patrón architect/worker cross-provider.
- L2: Inicio de implementación. server.py tiene _run_tool en línea 1195, _describe_tool en 1165, AGENT_TOOLS en línea 51, __init__ en 84. Los clients están en chat/chatgpt.py, chat/agy.py, chat/claude.py. EventEmitter es simple (JSON por línea a stdout). El directorio work/ ya existe con activity.py, explorer.py, etc.
- L3: T1-T6 completados en un solo commit c847cd6. 30 tests GREEN, 327 tests de regresión GREEN. Se incluyó T3 (cross-provider workers) directamente en worker.py como métodos del mismo WorkerRouter. QuotaAwareRouter soporta prioridad configurable via worker_priority.json. Eventos worker.* integrados directamente en WorkerRouter.run(). Se actualizó test existente (test_patch_and_files.py) para incluir delegate en AGENT_TOOLS.
- L4: Risk: none — no se toca datos persistentes, auth, ni contratos públicos. Los cambios son aditivos (nuevo módulo, nueva tool, nuevo case en _run_tool).
- L5: T7 — Unified mode toggle. Backend: `unified_mode` flag en server.py, `AGENT_TOOLS_BASE`/`AGENT_TOOLS_UNIFIED` condicional, comando `unified.toggle`, `unified_mode` en evento `provider.state`. UI: `unifiedMode` property + `toggleUnifiedMode()` en AgentBridge, botón glassmorphism "Unified" en topHeaderBar anclado a la izquierda del profileHeaderButton. 30 worker tests GREEN. Risk: none — UI toggle aditivo, no toca auth ni datos.
- L6 (2026-11-23): "Estaba usando opus 4.6 en vez de opus 5.5 puedes mejorar todo el sistema de arquitectura que hicimos para implementarlo con lo mas reciente hasta ahora". Correcciones a L3-L5: QuotaAwareRouter no estaba conectado; los modelos fijos no existían en `agy`; el esquema estricto era inválido; un error de Claude contaba como completado (RED reproducido); el modo unificado no hacía nada con arquitecto Claude o Gemini; las pruebas usaban eventos inventados; el fallo de `jwt` fue por usar el Python del sistema.
- L7: GREEN 352 pruebas. Prueba real: Opus 5.5 delegó a gemini-3.8-flash-medium y verificó, 22 s. Obrero Haiku aislado: de 39k a 7k tokens frescos. Pendiente: los obreros Claude no tienen permiso para comandos Bash generales (decisión del usuario). Risk: item 4 (cancelación compartida entre arquitecto y obrero), cubierto por test.
- L8 (2026-11-23): S18 pedido por el usuario. `UnifiedTeam.qml` muestra arquitecto, obrero por nivel, cuota y obrero activo (evento `unified.worker`). GREEN 354 pruebas y capturas offscreen en 820x760 y 480x620. Risk: none.
- L9 (2026-11-23): S19 pedido por el usuario. `UnifiedUsageWindows.qml`/`ProviderUsageWindow.qml`, comando `unified.usage`, evento `usage.provider`, rol 21 en `place-text-viewer.py`, `unified-smoke.qml`. GREEN 358 pruebas, smoke 3/3, geometría real en Hyprland 268/269/269 px sobre el chat de 826 px. Risk: none.

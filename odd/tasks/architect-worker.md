# Architect/Worker Cross-Provider Pattern

Branch: `feat/architect-worker`
Delivery: `ask-on-risk` (default)
Test runner: `python -m pytest tests/backend/work/ -x -q`

## Specs

- S1: `WorkerResult` dataclass con campos: `status` ("completed"|"failed"|"interrupted"|"quota_exhausted"), `summary` (str), `files_changed` (list of dicts con path/action), `tool_calls` (int), `tokens_used` (dict input/output/total), `provider` (str), `model` (str), `error` (str).
- S2: `DELEGATE_TOOL` — definición OpenAI-compatible con parámetros: `task` (str, required), `provider` (str, enum chatgpt/agy/claude, optional), `model` (str, optional), `max_steps` (int, optional, default 16). `strict: True`.
- S3: `WORKER_INSTRUCTIONS` — instrucciones acotadas para el worker: responde en el idioma del task, usa las herramientas disponibles, completa la tarea y resume qué hiciste y qué archivos tocaste.
- S4: `WorkerRouter` con método `run(task, provider, model, control, max_steps) -> WorkerResult`. Constructor recibe `chatgpt_client`, `agy_client`, `claude_client`, `session`, `workspace`, `event_callback`.
- S5: `WorkerRouter._chatgpt_worker` — mini step-loop con `client.stream()`, `AGENT_TOOLS`, y ejecución de tools via `_execute_tool`. Captura `files_changed` directamente.
- S6: `WorkerRouter._agy_worker` — lanza `agy_client.stream_turn(task, model, workspace, control)`, captura events, infiere `files_changed` de tool events (apply_patch→modified, shell write→created).
- S7: `WorkerRouter._claude_worker` — lanza `claude_client.stream_turn(task, model, workspace, control)`, captura events, infiere `files_changed` de tool events.
- S8: Integración en `server.py`: agregar `DELEGATE_TOOL` a `AGENT_TOOLS`, agregar case `"delegate"` en `_describe_tool` y `_run_tool`, instanciar `WorkerRouter` en `__init__`.
- S9: `QuotaAwareRouter` con `select_worker(preferred_provider, preferred_model) -> (provider, model)`, `run(task, control, ...) -> WorkerResult`, tabla de prioridad configurable `WORKER_PRIORITY`, detección de errores de cuota por proveedor, fallback automático con reintento.
- S10: Eventos `worker.started` (provider, model, task_preview), `worker.tool` (tool_name, command, status), `worker.text` (text), `worker.finished` (WorkerResult serializado), `worker.fallback` (from_provider, to_provider, reason).
- S11: Tests unitarios con fake clients para WorkerRouter y QuotaAwareRouter.

## Tasks

- T1 [S1,S2,S3,S4,S5] Foundation: WorkerResult + DELEGATE_TOOL + WORKER_INSTRUCTIONS + WorkerRouter con _chatgpt_worker — inline
- T2 [S8] Integration: wire delegate en server.py (_describe_tool, _run_tool, AGENT_TOOLS, __init__) — inline
- T3 [S6,S7] Cross-provider: _agy_worker + _claude_worker en WorkerRouter — inline
- T4 [S9] QuotaAwareRouter: selección, detección de cuota, fallback — inline
- T5 [S10] Worker events: emitir worker.* desde WorkerRouter — inline
- T6 [S11] Tests: WorkerRouter + QuotaAwareRouter con fakes — inline

## Log

- L1: "Puedes implementar todo esta arquitectura en mi proyecto" — usuario pide implementar el diseño completo del patrón architect/worker cross-provider.
- L2: Inicio de implementación. server.py tiene _run_tool en línea 1195, _describe_tool en 1165, AGENT_TOOLS en línea 51, __init__ en 84. Los clients están en chat/chatgpt.py, chat/agy.py, chat/claude.py. EventEmitter es simple (JSON por línea a stdout). El directorio work/ ya existe con activity.py, explorer.py, etc.

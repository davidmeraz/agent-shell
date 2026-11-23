"""Compactación inteligente de contexto y relevo (handoff) tras N compactaciones.

- Conserva intactos los pares function_call / function_call_output y el bootstrap inicial.
- Hasta `max_compactions` (3 por defecto) compacta el contexto dentro del mismo chat sin
  borrar el historial visible.
- Al superar el límite, genera un relevo filtrado con lo que realmente aporta al software
  (apoyado en el estado Git real del proyecto) para arrancar un chat nuevo y limpio.
"""

from __future__ import annotations

import copy
import json
from pathlib import Path

from ..core.http import ServiceError, StreamControl
from ..work.bootstrap import build_work_bootstrap, git_software_context

BOOTSTRAP_PREFIX = "Workspace snapshot ("
COMPACTION_HEADER = "Compacted conversation checkpoint (authoritative summary of earlier turns):\n"
HANDOFF_HEADER = (
    "Handoff summary from the previous chat (use together with the fresh workspace snapshot "
    "and recent git commits above; discard any outdated assumptions if files on disk differ):\n"
)
MAX_TRANSCRIPT_CHARS = 48000
MAX_TOOL_SNIPPET = 1200

COMPACT_INSTRUCTIONS = (
    "You are compacting earlier conversation history for an AI coding harness. "
    "Write in the same language as the conversation. Be concise, factual, and dense. "
    "Produce a structured checkpoint with ONLY information still useful to continue the work:\n"
    "1. Objective & current scope\n"
    "2. Key architectural decisions, constraints & invariants\n"
    "3. Files modified/created and current verified state (reconciled with git context if provided)\n"
    "4. Tests/checks run and their latest real results\n"
    "5. Open blockers and concrete next steps\n"
    "Do NOT reproduce raw file contents, long logs, or resolved dead ends."
)

HANDOFF_INSTRUCTIONS = (
    "You are preparing a clean software engineering handoff for a BRAND NEW chat session "
    "after the previous chat reached its 3-compaction limit. Write in the same language as the user. "
    "Filter aggressively: keep ONLY high-signal knowledge that genuinely contributes to building "
    "and maintaining the user's software, grounded in the real git commits and workspace state provided.\n"
    "Discard old debugging noise, failed attempts, transient errors, and superseded plans.\n"
    "Use these exact sections:\n"
    "1. Software goal & current focus\n"
    "2. Architecture, contracts & invariants that must be preserved\n"
    "3. Real current state of the codebase (aligned with recent git commits & modified files)\n"
    "4. Verification commands & quality gates\n"
    "5. Concrete next tasks & unresolved decisions"
)


def is_bootstrap_item(item: dict) -> bool:
    return (
        isinstance(item, dict)
        and item.get("role") == "developer"
        and isinstance(item.get("content"), str)
        and item["content"].startswith(BOOTSTRAP_PREFIX)
    )


def _safe_user_cut_indices(items: list[dict], start: int) -> list[int]:
    """Devuelve índices seguros donde comienza un turno de usuario sin llamadas pendientes."""
    pending_calls: set[str] = set()
    cuts: list[int] = []
    for idx in range(start, len(items)):
        item = items[idx]
        kind = item.get("type", "message")
        if kind == "message" and item.get("role") == "user" and not pending_calls:
            cuts.append(idx)
        elif kind == "function_call" and isinstance(item.get("call_id"), str):
            pending_calls.add(item["call_id"])
        elif kind == "function_call_output" and isinstance(item.get("call_id"), str):
            pending_calls.discard(item["call_id"])
    return cuts


def split_for_compaction(context: list[dict], keep_recent_turns: int = 1) -> tuple[list[dict], list[dict], list[dict]]:
    """Separa `context` en `(bootstrap_prefix, to_summarize, recent_tail)` sin romper tool pairs."""
    if not context:
        return [], [], []
    start = 1 if is_bootstrap_item(context[0]) else 0
    prefix = copy.deepcopy(context[:start])
    if len(context) <= start:
        return prefix, [], []

    cuts = _safe_user_cut_indices(context, start)
    if keep_recent_turns > 0 and len(cuts) > keep_recent_turns:
        cut_at = cuts[-keep_recent_turns]
        older = context[start:cut_at]
        tail = copy.deepcopy(context[cut_at:])
    else:
        # Si solo hay un turno largo (o keep_recent_turns == 0), resumir todo lo seguro.
        older = context[start:]
        tail = []
    return prefix, older, tail


def render_for_summary(items: list[dict], max_chars: int = MAX_TRANSCRIPT_CHARS) -> str:
    """Convierte items de Responses a texto compacto sin base64 ni razonamiento cifrado."""
    blocks: list[str] = []
    for item in items:
        kind = item.get("type", "message")
        if kind == "reasoning":
            continue
        if kind == "message":
            role = str(item.get("role", "assistant")).upper()
            content = item.get("content", "")
            if isinstance(content, str):
                text = content.strip()
            elif isinstance(content, list):
                parts = []
                for part in content:
                    if not isinstance(part, dict):
                        continue
                    ptype = part.get("type")
                    if ptype in ("input_text", "output_text"):
                        parts.append(part.get("text", ""))
                    elif ptype == "refusal":
                        parts.append("[Rechazo] " + part.get("refusal", ""))
                    elif ptype == "input_image":
                        parts.append("[Imagen adjunta omitida en compactación]")
                text = "\n".join(p for p in parts if p).strip()
            else:
                text = ""
            if text:
                blocks.append(f"[{role}]\n{text[:4000]}")
        elif kind == "function_call":
            name = item.get("name", "tool")
            args = str(item.get("arguments", ""))[:600]
            blocks.append(f"[TOOL_CALL {name}] {args}")
        elif kind == "function_call_output":
            raw = str(item.get("output", ""))
            try:
                parsed = json.loads(raw)
                status = parsed.get("status", "")
                code = parsed.get("exit_code")
                out = str(parsed.get("output", ""))
                if len(out) > MAX_TOOL_SNIPPET:
                    half = MAX_TOOL_SNIPPET // 2
                    out = out[:half] + "\n[…]\n" + out[-half:]
                blocks.append(f"[TOOL_RESULT status={status} exit={code}]\n{out}")
            except (ValueError, TypeError, AttributeError):
                blocks.append(f"[TOOL_RESULT]\n{raw[:MAX_TOOL_SNIPPET]}")
    joined = "\n\n".join(blocks).strip()
    if len(joined) > max_chars:
        half = (max_chars - 32) // 2
        joined = joined[:half] + "\n\n[… historial intermedio omitido …]\n\n" + joined[-half:]
    return joined


def summarize_context(
    client,
    model: str,
    items: list[dict],
    control: StreamControl,
    *,
    handoff: bool = False,
    workspace: Path | None = None,
    effort: str = "",
) -> str:
    """Solicita al modelo un checkpoint o handoff estructurado sin herramientas."""
    transcript = render_for_summary(items)
    if not transcript:
        raise ValueError("Todavía no hay suficiente contexto para compactar.")
    git_block = git_software_context(workspace) if workspace is not None else ""
    sections = []
    if git_block:
        sections.append("Current real Git state of the project:\n" + git_block)
    sections.append("Conversation history to distill:\n" + transcript)
    prompt = "\n\n---\n\n".join(sections)

    instructions = HANDOFF_INSTRUCTIONS if handoff else COMPACT_INSTRUCTIONS
    # Nunca usamos herramientas ni mutamos el historial durante el resumen.
    stream = client.stream(
        model,
        [{"role": "user", "content": prompt}],
        instructions,
        control,
        tools=None,
        reasoning_effort=effort,
    )
    chunks: list[str] = []
    completed = None
    try:
        for event in stream:
            control.check()
            kind = event.get("type")
            if kind == "response.output_text.delta" and isinstance(event.get("delta"), str):
                chunks.append(event["delta"])
            elif kind == "response.completed":
                completed = event.get("response") or {}
                if completed.get("status") != "completed":
                    raise ServiceError("No se confirmó el final de la compactación.")
                break
            elif kind in ("response.failed", "response.incomplete", "error"):
                raise ServiceError("No se pudo generar el resumen de compactación.")
    finally:
        close = getattr(stream, "close", None)
        if close:
            close()
    if completed is None:
        control.check()
        raise ServiceError("La compactación terminó antes de completarse.")

    final_parts = [
        part.get("text", "")
        for item in completed.get("output", [])
        if isinstance(item, dict) and item.get("type") == "message" and item.get("role") == "assistant"
        for part in item.get("content", [])
        if isinstance(part, dict) and part.get("type") == "output_text"
    ]
    text = ("\n".join(p for p in final_parts if p) or "".join(chunks)).strip()
    if not text:
        raise ServiceError("El modelo devolvió un resumen vacío al compactar.")
    return text


def build_compacted_context(
    prefix: list[dict], summary: str, recent_tail: list[dict],
) -> list[dict]:
    return prefix + [{"role": "developer", "content": COMPACTION_HEADER + summary}] + recent_tail


def build_handoff_context(
    summary: str, *, area: str, workspace: Path | None, history_root: Path | None = None,
) -> list[dict]:
    items: list[dict] = []
    if area in ("work", "app") and workspace is not None:
        ignored = (history_root,) if history_root is not None else ()
        bootstrap = build_work_bootstrap(workspace, ignored=ignored)
        if bootstrap:
            items.append({"role": "developer", "content": bootstrap})
    items.append({"role": "developer", "content": HANDOFF_HEADER + summary})
    return items


def handoff_title(original_title: str) -> str:
    base = original_title.removesuffix(" (continuación)").strip() or "Conversación"
    suffix = " (continuación)"
    return (base[:72 - len(suffix)].rstrip() + suffix)[:72]

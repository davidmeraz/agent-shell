"""Familias y esfuerzos admitidos; el catálogo de la cuenta tiene prioridad."""

import re

EFFORTS = ("none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra")
# Compatibilidad publicada por OpenAI. No se inventan niveles para slugs desconocidos.
# https://developers.openai.com/api/docs/guides/reasoning
DOCUMENTED = {
    "gpt-6.1-sol": ("low", "medium", "high", "xhigh", "max"),
    "gpt-6-astra": ("low", "medium", "high", "xhigh", "max"),
    "gpt-6-sol": ("none", "low", "medium", "high", "xhigh", "max"),
    "gpt-6-luna": ("none", "low", "medium", "high", "xhigh", "max"),
    "gpt-5.6-sol": ("none", "low", "medium", "high", "xhigh", "max"),
    "gpt-5.6": ("none", "low", "medium", "high", "xhigh", "max"),
    "gpt-5.4": ("none", "low", "medium", "high", "xhigh"),
}


def family(slug: str) -> str:
    match = re.match(r"^(gpt-\d+)(?:[.-]|$)", slug.lower())
    return match[1] if match else "otros"


def model_options(raw: dict) -> dict:
    slug = raw["slug"]
    base = re.sub(r"-\d{4}-\d{2}-\d{2}$", "", slug)
    advertised = raw.get("supported_reasoning_levels", raw.get("supported_reasoning_efforts"))
    if isinstance(advertised, list):
        levels = [item.get("effort") if isinstance(item, dict) else item for item in advertised]
        levels = [effort for effort in EFFORTS if effort in levels]
    else:
        levels = list(DOCUMENTED.get(base, ()))
    default = raw.get("default_reasoning_level", raw.get("default_reasoning_effort", ""))
    if default not in levels:
        default = "none" if base == "gpt-5.4" and "none" in levels else "medium" if "medium" in levels else ""
    return {"slug": slug, "display_name": raw.get("display_name") or slug,
            "family": family(slug), "reasoning_efforts": levels, "default_reasoning_effort": default}


def validate_effort(model: dict, effort) -> str:
    if not isinstance(effort, str) or (effort and effort not in model.get("reasoning_efforts", [])):
        raise ValueError("Ese esfuerzo de razonamiento no está disponible para el modelo seleccionado.")
    return effort

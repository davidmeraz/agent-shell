"""Contexto de Responses persistido: llamadas/resultados y razonamiento cifrado.

El razonamiento en texto no se guarda ni se envía a Qt. La carga nunca ejecuta
llamadas del historial; los trabajos pendientes se cierran como interrumpidos.
"""

import copy
import json

from .images import validate_image


def replay_items(items: list) -> list[dict]:
    if not isinstance(items, list):
        raise ValueError("Contexto de Responses inválido")
    result = []
    for value in items:
        if not isinstance(value, dict):
            raise ValueError("Elemento de contexto inválido")
        kind = value.get("type", "message")
        if kind == "message":
            if value.get("role") not in ("user", "assistant", "system", "developer"):
                raise ValueError("Rol de contexto inválido")
            content = value.get("content")
            if not isinstance(content, (str, list)):
                raise ValueError("Contenido de contexto inválido")
            if isinstance(content, list):
                for part in content:
                    if not isinstance(part, dict):
                        raise ValueError("Contenido de contexto inválido")
                    if part.get("type") == "input_image":
                        if value["role"] != "user" or part.get("detail", "auto") not in ("auto", "low", "high"):
                            raise ValueError("Imagen de contexto inválida")
                        validate_image(part.get("image_url"))
                    elif (part.get("type") not in ("input_text", "output_text", "refusal")
                          or not isinstance(part.get("refusal" if part.get("type") == "refusal" else "text"), str)):
                        raise ValueError("Texto de contexto inválido")
            result.append(copy.deepcopy(value))
        elif kind == "reasoning":
            item = {"type": "reasoning", "summary": []}
            if isinstance(value.get("id"), str):
                item["id"] = value["id"]
            if isinstance(value.get("encrypted_content"), str):
                item["encrypted_content"] = value["encrypted_content"]
            result.append(item)
        elif kind == "function_call":
            if not all(isinstance(value.get(key), str) and value[key] for key in ("call_id", "name")):
                raise ValueError("Identidad de herramienta inválida")
            if not isinstance(value.get("arguments"), str):
                raise ValueError("Argumentos de herramienta inválidos")
            result.append({key: value[key] for key in ("type", "call_id", "name", "arguments", "id") if key in value})
        elif kind == "function_call_output":
            if not isinstance(value.get("call_id"), str) or not isinstance(value.get("output"), str):
                raise ValueError("Resultado de herramienta inválido")
            result.append({"type": kind, "call_id": value["call_id"], "output": value["output"]})
        else:
            raise ValueError("El servicio solicitó una herramienta no compatible")
    return result


def visible_chat(record: dict) -> dict:
    return {key: value for key, value in record.items() if key != "context"}


def append_result(record: dict, call_id: str, result: dict) -> None:
    record["context"].append({"type": "function_call_output", "call_id": call_id,
                              "output": json.dumps(result, ensure_ascii=False)})


def close_pending_calls(record: dict) -> None:
    context = record.get("context", [])
    done = {item["call_id"] for item in context if item.get("type") == "function_call_output"}
    for item in list(context):
        if item.get("type") == "function_call" and item["call_id"] not in done:
            append_result(record, item["call_id"], {"status": "interrupted", "output": "Turno interrumpido; no reejecutar esta llamada."})
            done.add(item["call_id"])
    for call in record.get("tool_calls", []):
        if call["status"] in ("pending", "running"):
            call["status"] = "interrupted"

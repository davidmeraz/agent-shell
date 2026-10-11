#!/usr/bin/env python3
"""Doble de prueba de App Server: no usa red, credenciales ni un modelo real.

Sólo se selecciona explícitamente en scripts/smoke.sh o pruebas. La aplicación
normal inicia el ejecutable codex de PATH.
"""

import json
import os
import sys
import uuid


def write(message):
    print(json.dumps(message, ensure_ascii=False), flush=True)


def notify(method, params):
    write({"method": method, "params": params})


def main():
    account_type = os.environ.get("AGENT_SHELL_TEST_AUTH", "chatgpt")
    thread_count = turn_count = 0
    active_thread = active_turn = None
    for line in sys.stdin:
        request = json.loads(line)
        if "id" not in request or "method" not in request:
            continue
        method, params = request["method"], request.get("params", {})

        def reply(result):
            write({"id": request["id"], "result": result})

        if method == "initialize":
            reply({"userAgent": "fake-codex-for-tests"})
        elif method == "account/read":
            account = {"type": account_type} if account_type else None
            if account_type == "chatgpt":
                account.update(email="fixture@example.invalid", planType="plus")
            reply({"account": account, "requiresOpenaiAuth": True})
        elif method == "account/login/start":
            reply({"type": "chatgpt", "loginId": "login-test", "authUrl": "https://auth.openai.com/test-only"})
        elif method == "account/login/cancel":
            reply({})
            notify("account/login/completed", {"loginId": params["loginId"], "success": False, "error": "Cancelado"})
        elif method == "thread/start":
            thread_count += 1
            active_thread = f"thread-{uuid.uuid4().hex}"
            reply({"thread": {"id": active_thread}, "model": "modelo-de-prueba"})
        elif method == "thread/resume":
            active_thread = params["threadId"]
            reply({"thread": {"id": active_thread}, "model": "modelo-de-prueba"})
        elif method == "turn/start":
            turn_count += 1
            active_thread = params["threadId"]
            active_turn = f"turn-{uuid.uuid4().hex}"
            prompt = params["input"][0]["text"]
            turn = {"id": active_turn, "status": "inProgress", "error": None}
            reply({"turn": turn})
            notify("turn/started", {"threadId": active_thread, "turn": turn})
            envelope = {"threadId": active_thread, "turnId": active_turn, "itemId": f"item-{active_turn}"}
            if prompt == "fail":
                turn.update(status="failed", error={"message": "Error de prueba del proveedor"})
                notify("turn/completed", {"threadId": active_thread, "turn": turn})
            else:
                notify("item/agentMessage/delta", {**envelope, "delta": "Hola "})
                if prompt == "cancel":
                    continue  # El turno permanece activo hasta turn/interrupt.
                notify("item/agentMessage/delta", {**envelope, "delta": "desde Codex. 🎵"})
                notify("item/completed", {"threadId": active_thread, "turnId": active_turn,
                       "item": {"id": envelope["itemId"], "type": "agentMessage", "text": "Hola desde Codex. 🎵"}})
                turn.update(status="completed")
                notify("turn/completed", {"threadId": active_thread, "turn": turn})
        elif method == "turn/interrupt":
            reply({})
            notify("turn/completed", {"threadId": params["threadId"],
                   "turn": {"id": params["turnId"], "status": "interrupted", "error": None}})
        else:
            write({"id": request["id"], "error": {"code": -32601, "message": "Método no simulado"}})


if __name__ == "__main__":
    main()

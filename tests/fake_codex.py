"""Servidor RPC de prueba aislado: nunca llama a Codex ni lee una sesión real."""

import json
import sys
import time


def limits():
    return {"rateLimitsByLimitId": {
        "codex": {"limitId": "codex", "limitName": "Codex",
                  "primary": {"usedPercent": 25, "windowDurationMins": 300, "resetsAt": 1893456000},
                  "secondary": {"usedPercent": 60, "windowDurationMins": 10080, "resetsAt": 1893542400},
                  "credits": {"hasCredits": True, "unlimited": False, "balance": "12.5"}},
        "review": {"limitName": "Revisión", "primary": None, "secondary": None}}}


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "ok"
    account_reads = 0
    for raw in sys.stdin:
        request = json.loads(raw)
        method = request["method"]
        if "id" not in request:
            assert method == "initialized"
            continue
        if mode == "timeout":
            time.sleep(30)
        if mode == "eof":
            return
        if mode == "invalid_json":
            print("not json", flush=True)
            continue
        if mode == "oversized":
            print("x" * (3 * 1024 * 1024), flush=True)
            continue
        response = {"id": request["id"]}
        if method == "initialize":
            response["result"] = {"userAgent": "fixture"}
        elif method == "account/read":
            account_reads += 1
            response["result"] = {"account": None if mode == "logged_out" else {
                "type": "apiKey" if mode == "api_key" else "chatgpt",
                "email": "other@example.invalid" if mode == "mismatch" or (mode == "changed" and account_reads > 1)
                else "fixture@example.invalid", "planType": "plus"}}
        elif method == "account/rateLimits/read":
            if mode == "rpc_error":
                response["error"] = {"code": -1, "message": "DO_NOT_EXPOSE_ACCESS_TOKEN"}
            else:
                response["result"] = limits()
                if mode == "invalid_number":
                    response["result"]["rateLimitsByLimitId"]["codex"]["primary"]["usedPercent"] = True
        elif method == "account/usage/read":
            if mode == "optional":
                response["error"] = {"code": -32601, "message": "Method unavailable"}
            else:
                response["result"] = {"summary": {"lifetimeTokens": 78714500}, "dailyUsageBuckets": []}
        else:
            raise AssertionError("El lector solicitó una operación ajena al uso")
        # Varias líneas en un solo write detectan la regresión select + readline con buffering.
        sys.stdout.write(json.dumps({"method": "account/rateLimits/updated", "params": {}}) + "\n"
                         + json.dumps(response) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()

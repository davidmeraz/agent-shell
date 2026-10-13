"""Catálogo y Responses de ChatGPT; la ejecución de herramientas pertenece al backend."""

from ..account.auth import RESOURCE, ChatGPTSession
from ..core.http import HttpClient, ServiceError, StreamControl
from .models import EFFORTS, model_options


class ChatGPTClient:
    def __init__(self, session: ChatGPTSession, http: HttpClient | None = None,
                 base_url: str = RESOURCE) -> None:
        self.session = session
        self.http = http or HttpClient()
        self.base_url = base_url

    def models(self) -> list[dict]:
        token = self.session.access_token()
        value = self.http.json("GET", self.base_url + "/models",
                               headers={"Authorization": "Bearer " + token})
        models = value.get("models")
        if not isinstance(models, list):
            raise ServiceError("El catálogo de modelos es incompatible")
        result = []
        for model in models:
            if (isinstance(model, dict) and model.get("visibility") == "list"
                    and isinstance(model.get("slug"), str) and model["slug"]):
                result.append(model_options(model))
        if not result:
            raise ServiceError("No hay modelos disponibles para tu cuenta. Revisa el acceso a tu plan.")
        return result

    def stream(self, model: str, messages: list[dict], instructions: str, control: StreamControl,
               tools: list[dict] | None = None, reasoning_effort: str = ""):
        if not isinstance(reasoning_effort, str) or (reasoning_effort and reasoning_effort not in EFFORTS):
            raise ValueError("Esfuerzo de razonamiento inválido")
        control.check()
        control.mark("session_start")
        token = self.session.access_token()
        control.mark("session_end")
        control.check()
        # El contexto es local. store=false impide depender de threads o respuestas remotas guardadas.
        payload = {"model": model, "instructions": instructions, "input": messages,
                   "store": False, "stream": True}
        if reasoning_effort:
            payload["reasoning"] = {"effort": reasoning_effort}
        if tools is not None:
            payload.update(tools=tools, parallel_tool_calls=False, include=["reasoning.encrypted_content"])
        # Algunos streams del plan entregan los elementos completos en
        # output_item.done y dejan vacío el output del resumen final.
        # Sólo reconstruimos después de recibir response.completed; un item
        # completo por sí solo nunca autoriza la ejecución de herramientas.
        finished_items = {}
        for event in self.http.stream(self.base_url + "/responses", payload, token, control):
            if tools is not None and event["type"] == "response.output_item.done":
                index, item = event.get("output_index"), event.get("item")
                if type(index) is not int or not 0 <= index < 128 or not isinstance(item, dict):
                    raise ServiceError("El servicio devolvió un elemento incompatible")
                if index in finished_items:
                    raise ServiceError("El servicio repitió un elemento de respuesta")
                finished_items[index] = item
            if tools is not None and event["type"] == "response.completed":
                response = event.get("response")
                if isinstance(response, dict) and not response.get("output") and finished_items:
                    event = {**event, "response": {**response, "output": [
                        finished_items[index] for index in sorted(finished_items)
                    ]}}
            yield event

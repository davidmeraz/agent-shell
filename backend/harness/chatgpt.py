"""Catálogo y respuestas de ChatGPT sin proceso hijo ni herramientas de agente."""

from .auth import RESOURCE, ChatGPTSession
from .http import HttpClient, ServiceError, StreamControl


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
                result.append({"slug": model["slug"], "display_name": model.get("display_name") or model["slug"]})
        if not result:
            raise ServiceError("No hay modelos disponibles para tu cuenta. Revisa el acceso a tu plan.")
        return result

    def stream(self, model: str, messages: list[dict], instructions: str, control: StreamControl):
        control.check()
        token = self.session.access_token()
        control.check()
        # El contexto es local. store=false impide depender de threads o respuestas remotas guardadas.
        payload = {"model": model, "instructions": instructions, "input": messages,
                   "store": False, "stream": True}
        yield from self.http.stream(self.base_url + "/responses", payload, token, control)

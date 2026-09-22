"""HTTP service for DevOps assessment"""

from __future__ import annotations

import os
import threading
from typing import Dict

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field, field_validator

APP_VERSION = os.getenv("APP_VERSION", "1.0.0")

app = FastAPI(title="confapi", version=APP_VERSION)

_store: Dict[str, str] = {}
_lock = threading.Lock()


class ConfigItem(BaseModel):
    name: str = Field(..., min_length=1)
    value: str

    @field_validator("name")
    @classmethod
    def name_not_blank(cls, value: str) -> str:
        stripped = value.strip()
        if not stripped:
            raise ValueError("name must not be blank")
        return stripped


class HealthResponse(BaseModel):
    status: str


class VersionResponse(BaseModel):
    version: str


class EnvResponse(BaseModel):
    environment: str


class DeleteResponse(BaseModel):
    deleted: bool


@app.get("/health", response_model=HealthResponse)
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/ready", response_model=HealthResponse)
def ready() -> dict[str, str]:
    return health()


@app.get("/version", response_model=VersionResponse)
def version() -> dict[str, str]:
    return {"version": os.getenv("APP_VERSION", APP_VERSION)}


@app.get("/env", response_model=EnvResponse)
def env() -> dict[str, str]:
    return {"environment": os.getenv("ENVIRONMENT", "")}


@app.post("/config", response_model=ConfigItem)
def set_config(item: ConfigItem) -> ConfigItem:
    with _lock:
        _store[item.name] = item.value
    return item


@app.get("/config/{name}", response_model=ConfigItem)
def get_config(name: str) -> dict[str, str]:
    with _lock:
        value = _store.get(name)
    if value is None:
        raise HTTPException(status_code=404, detail=f"config '{name}' not found")
    return {"name": name, "value": value}


@app.delete("/config/{name}", response_model=DeleteResponse)
def delete_config(name: str) -> dict[str, bool]:
    with _lock:
        if name not in _store:
            raise HTTPException(status_code=404, detail=f"config '{name}' not found")
        del _store[name]
    return {"deleted": True}

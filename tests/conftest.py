import os
import pytest

from app import main as app_main

@pytest.fixture(autouse=True)
def reset_app_state() -> None:
    with app_main._lock:
        app_main._store.clear()
    os.environ["ENVIRONMENT"] = "test"
    os.environ.pop("APP_VERSION", None)

import os

from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_ready() -> None:
    response = client.get("/ready")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_version_default() -> None:
    response = client.get("/version")
    assert response.status_code == 200
    assert response.json() == {"version": "1.0.0"}


def test_version_from_env() -> None:
    os.environ["APP_VERSION"] = "9.9.9"
    response = client.get("/version")
    assert response.json() == {"version": "9.9.9"}


def test_env() -> None:
    response = client.get("/env")
    assert response.status_code == 200
    assert response.json() == {"environment": "test"}


def test_config_roundtrip() -> None:
    created = client.post(
        "/config",
        json={"name": "database_url", "value": "postgres://example"},
    )
    assert created.status_code == 200
    assert created.json() == {
        "name": "database_url",
        "value": "postgres://example",
    }

    fetched = client.get("/config/database_url")
    assert fetched.status_code == 200
    assert fetched.json() == created.json()


def test_config_overwrite() -> None:
    client.post("/config", json={"name": "feature", "value": "off"})
    updated = client.post("/config", json={"name": "feature", "value": "on"})
    assert updated.json()["value"] == "on"
    assert client.get("/config/feature").json()["value"] == "on"


def test_get_missing_config() -> None:
    response = client.get("/config/missing")
    assert response.status_code == 404


def test_delete_config() -> None:
    client.post("/config", json={"name": "token", "value": "secret"})
    deleted = client.delete("/config/token")
    assert deleted.status_code == 200
    assert deleted.json() == {"deleted": True}
    assert client.get("/config/token").status_code == 404


def test_delete_missing_config() -> None:
    response = client.delete("/config/missing")
    assert response.status_code == 404


def test_post_rejects_empty_name() -> None:
    response = client.post("/config", json={"name": "", "value": "x"})
    assert response.status_code == 422


def test_post_rejects_blank_name() -> None:
    response = client.post("/config", json={"name": "   ", "value": "x"})
    assert response.status_code == 422


def test_post_strips_name() -> None:
    created = client.post("/config", json={"name": "  feature  ", "value": "on"})
    assert created.status_code == 200
    assert created.json()["name"] == "feature"
    assert client.get("/config/feature").status_code == 200


def test_post_rejects_missing_fields() -> None:
    response = client.post("/config", json={"name": "only_name"})
    assert response.status_code == 422

# Application and Requirements

To create a small service with endpoints below, it needs to be considered that should be written in **Go** or **Python**.
It seems a simpler script behaviour so I picked **Python**. Most probably in **Go** it'd be more reliable but more complex.
FastAPI Python framework seems to be a good choice that implements the HTTP service (app name: `confapi`).
Documentation:
https://fastapi.tiangolo.com/

## Endpoints

| Method    | Path              | Purpose                                       |
| ---       | ---               | ---                                           |
| `GET`     | `/health`         | Liveness payload `{"status":"ok"}`            |
| `GET`     | `/ready`          | Readiness payload `{"status":"ok"}`           |
| `GET`     | `/version`        | App version (`APP_VERSION`, default: `1.0.0`) |
| `GET`     | `/env`            | Value of the `ENVIRONMENT` variable           |
| `POST`    | `/config`         | Store a name/value pair in memory             |
| `GET`     | `/config/{name}`  | Read a stored value (`404` if missing)        |
| `DELETE`  | `/config/{name}`  | Delete a stored value (`404` if missing)      |

`POST /config` trims `name` and rejects blank names (HTTP 422).

Limitation:
The `/config` endpoint isn't persisted and isn't shared across pods or process restarts.
Postgres can be used later for persistence and multiple replicas.
`/ready` currently matches `/health`; it should check the backing store once one exists.
No authentication on write endpoints.

## Local run

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
pytest -q
uvicorn app.main:app --host 0.0.0.0 --port 8080
```

The process listens on **8080** so the Dockerfile, Helm Service and Ingress stay aligned.

# DevOps Engineer Homework

## Overview

Kubernetes resources' name: **confapi**.
The Helm release, namespace, minikube profile and Terraform resources' name: **sandbox**.
The application listens on **8080**.

## Repository Contents

```
app/                Python app with FastAPI framework ('confapi')
tests/              pytest tests
scripts/            docker-build, minikube-deploy
certs/              optional CAs (*.crt gitignored)
helm/               Kubernetes chart ('confapi')
terraform/          Namespace + helm_release ('sandbox')
Dockerfile          Image used by Helm and CI (Alpine 3.22)
.gitlab-ci.yml      stages: test, validate, build, deploy
REVIEW.md           Goal 2 review
```

## Goal 1

### Application

- Implemented the endpoints in FastAPI (`app/main.py`) as **confapi**.
- Stored `/config` values in a process-local dict with a lock that could save time.
- Returned **404** for unknown keys on GET/DELETE.
- Rejected empty or whitespace-only `name` on POST (HTTP 422).
- Added pytest coverage for the contract (`tests/test_api.py`).

| Method    | Path              | Purpose                                       |
| ---       | ---               | ---                                           |
| `GET`     | `/health`         | Liveness payload `{"status":"ok"}`            |
| `GET`     | `/ready`          | Readiness payload `{"status":"ok"}`           |
| `GET`     | `/version`        | App version (`APP_VERSION`, default: `1.0.0`) |
| `GET`     | `/env`            | Value of the `ENVIRONMENT` variable           |
| `POST`    | `/config`         | Store a name/value pair in memory             |
| `GET`     | `/config/{name}`  | Read a stored value (`404` if missing)        |
| `DELETE`  | `/config/{name}`  | Delete a stored value (`404` if missing)      |

```bash
python -m venv .venv
source .venv/bin/activate
pip install -r requirements-dev.txt
pytest -q
uvicorn app.main:app --host 0.0.0.0 --port 8080
```

```bash
curl -s localhost:8080/health
curl -s localhost:8080/ready
curl -s localhost:8080/version
ENVIRONMENT=dev curl -s localhost:8080/env
curl -s -X POST localhost:8080/config \
  -H 'content-type: application/json' \
  -d '{"name":"database_url","value":"postgres://example"}'
curl -s localhost:8080/config/database_url
curl -s -X DELETE localhost:8080/config/database_url
```

### Containerization

The image is `alpine:3.22` plus apk Python (not `python:*` Hub tags, which Docker Scout currently flags for high CVEs). The process runs as uid **10001** and owns `/opt/venv` and `/app`.

```bash
./scripts/docker-build.sh
docker run --rm -p 8080:8080 -e ENVIRONMENT=dev confapi:1.0.0
```

`scripts/docker-build.sh` copies CAs from `/usr/local/share/ca-certificates` into gitignored `certs/` so `pip` works behind TLS-inspecting proxies. Only `*.crt` files are installed into the image. GitLab can set `EXTRA_CA_CERT` (PEM text) for the same purpose when those files are not in git.

### Terraform

Terraform creates the namespace and installs the same chart. It doesn't create the cluster.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
```

CI deploys with Helm (`helm upgrade --install sandbox`) so GitLab doesn't need a Terraform state backend. `terraform-validate` only runs `fmt` / `init` / `validate`; it does not prove a cluster deploy.

- Added `required_providers` for `hashicorp/kubernetes` and `hashicorp/helm` 2.x.
- Pointed `helm_release.sandbox` at `${path.module}/../helm` instead of the non-existent `../helm/homework`.
- Wired `var.namespace`, `var.environment`, and `var.image_tag` into the release. The original `value =` for `image.tag` didn't parse; unquoted `prod` was an undeclared reference.
- Default namespace is `sandbox`, not `production`.
- `kube_context` is required so Terraform will not apply to the current kubeconfig context by accident.
- `atomic = true` rolls a failed Helm release back.

### Helm

- Chart name is `confapi`. Workload objects use `fullnameOverride: confapi`.
- The Helm release, namespace, and Minikube profile are `sandbox` (the original templates used `homeworks` as the Ingress backend).
- Templated names and shared selector labels so the Service actually selects pods (the original selector was `app: myapps`).
- Pointed Ingress at the chart Service name and Service port (the original backend was `homeworks:80`).
- Standardized on '8080' (`containerPort`, Service port, `targetPort`, Ingress).
- Honoured `replicaCount`, `image.tag`, `image.pullPolicy`, and `environment`.
- `app.kubernetes.io/version` follows `image.tag` (git SHA in CI).
- Liveness is `/health`, readiness is `/ready`.
- Added resource requests/limits and a non-root `securityContext` with a read-only root filesystem and `/tmp` emptyDir.

### What You Changed

- Details are described in REVIEW.md

### GitLab CI

- I didn't use GitLab CI pipeline YAML editor before so I wasn't sure about that implementation. Slightly extended with AI tool.
- Used documentations:

  https://docs.gitlab.com/ci/quick_start/tutorial/

  https://docs.gitlab.com/user/packages/package_registry/pypi_cosign_tutorial/

- `workflow.rules` run pipelines only for merge requests and the default branch (no duplicate MR + branch pipelines).
- Stages: `test`, `validate`, `build`, `deploy`. Image build waits for test + Helm lint + Terraform validate.
- `test` uses the same Alpine 3.22 digest as the Dockerfile.
- `build-job` uses Docker-in-Docker with `DOCKER_HOST=tcp://docker:2375` and `DOCKER_TLS_CERTDIR=""`. The GitLab runner must allow **privileged** DinD.
- Optional CI variable `EXTRA_CA_CERT`: PEM of an extra CA written to `certs/extra-ca.crt` before `docker build` (corporate TLS inspection). Do not commit `certs/*.crt`.
- `deploy` is **manual** on the default branch. It installs Helm release `sandbox` into namespace `sandbox`.
- Deploy image is `dtzar/helm-kubectl` (Helm 3.16.4 + kubectl). Do not `apk add kubectl` on `alpine/helm`.
- Cluster pulls need a registry secret that **outlives the job**. Create a GitLab Deploy Token named **`gitlab-deploy-token`** with `read_registry` so GitLab sets `CI_DEPLOY_USER` / `CI_DEPLOY_PASSWORD`. Without that, the job falls back to the job token and later pod restarts can `ImagePullBackOff`.
- Required CI variable: `KUBE_CONFIG` (base64-encoded kubeconfig). The job will not run against Minikube unless that cluster is reachable from the runner.

### Assumptions

- Missing config keys are '404', not empty documents.
- Local target is Minikube with `~/.kube/config`. No cloud account is required.
- Image `confapi:1.0.0` is loaded into the cluster rather than pulled from a registry, so local Helm uses `imagePullPolicy=Never`.
- CI deploy uses Helm, not `terraform apply`, to avoid remote state for this exercise.
- Extra CAs under `/usr/local/share/ca-certificates` are copied into `certs/` at local image-build time so pip can talk to PyPI behind TLS inspection.
- `myapp` is renamed to `confapi` (chart, image, Kubernetes object names) and `homeworks` is renamed to `sandbox` (Helm release, namespace, Minikube profile, Terraform resources).

### Known limitations

- I didn't use GitLab CI pipeline YAML editor before so I wasn't sure about that implementation. Slightly extended with AI tool.
- The `/config` endpoint isn't persisted and isn't shared across pods or process restarts.
- `/ready` does not yet check a backing store.
- No authentication on write endpoints.
- No remote Terraform state.
- The GitLab `deploy` job is manual and needs `KUBE_CONFIG`. It will not run against Minikube unless you expose that cluster to a runner.
- Helm 3 / Terraform Helm provider 2.x are pinned in CI and Terraform; this WSL host has Helm 4 for local `helm upgrade`. Helm provider 3 removes the nested `kubernetes {}` block and would need a provider refactor.
- On this WSL host the Minikube node cannot pull from `registry.k8s.io` through TLS inspection. `scripts/minikube-deploy.sh` pins Kubernetes **v1.37.0** (already cached on the host) and loads CNI/control-plane images from the host Docker daemon. The script uses port-forward on `127.0.0.1:18083` and tears it down after the `/health` check.

### Production Improvements

- Replace the in-memory map with a datastore (i.e.: PostgreSQL) and make `/ready` check it.
- Sign images and scan them on every pipeline.
- Terminate TLS with cert-manager; set `ingressClassName` explicitly.
- Store Terraform state remotely with locking; inject `TF_VAR_image_tag=$CI_COMMIT_SHORT_SHA`.
- Add structured logging, metrics (`/metrics`), and tracing.
- Split environments (`dev`/`staging`/`prod`) with separate namespaces and values files.

### Notes

#### Minikube

```bash
./scripts/minikube-deploy.sh
```

That will:

1. Install minikube and a current kubectl into `~/.local/bin` if needed
2. Start `--profile=sandbox --driver=docker --keep-context`
3. Build `confapi:1.0.0` and load it into the cluster
4. `helm upgrade --install sandbox` into namespace `sandbox` with `imagePullPolicy=Never`
5. Port-forward on `127.0.0.1:18083`, check `/health`, then stop the forward

Manual equivalent:

```bash
minikube start --profile=sandbox --driver=docker --keep-context
./scripts/docker-build.sh
minikube image load confapi:1.0.0 --profile=sandbox

helm upgrade --install sandbox ./helm \
  --kube-context sandbox \
  --namespace sandbox --create-namespace \
  --set image.repository=confapi \
  --set image.tag=1.0.0 \
  --set image.pullPolicy=Never \
  --set fullnameOverride=confapi \
  --set environment=dev \
  --wait

kubectl --context sandbox -n sandbox port-forward svc/confapi 8080:8080
```

$ minikube profile list
┌────────────┬────────┬────────────┬──────────────┬─────────┬─────────┬───────┬────────────────┬────────────────────┐
│  PROFILE   │ DRIVER │  RUNTIME   │      IP      │ VERSION │ STATUS  │ NODES │ ACTIVE PROFILE │ ACTIVE KUBECONTEXT │
├────────────┼────────┼────────────┼──────────────┼─────────┼─────────┼───────┼────────────────┼────────────────────┤
│ sandbox    │ docker │ containerd │ 192.168.85.2 │ v1.37.0 │ OK      │ 1     │                │                    │
└────────────┴────────┴────────────┴──────────────┴─────────┴─────────┴───────┴────────────────┴────────────────────┘

### Timing

I slipped out from the 3 hours timebox. The main reason was the newly used Gitlab CI pipeline task that I had to start to read the tutorials.

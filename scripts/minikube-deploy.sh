#!/usr/bin/env bash
# Start a dedicated Minikube profile and deploy this chart to it.
# Never uses or changes the current kubeconfig context.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PROFILE="${MINIKUBE_PROFILE:-sandbox}"
IMAGE_NAME="${IMAGE_NAME:-confapi}"
IMAGE_TAG="${IMAGE_TAG:-1.0.0}"
NAMESPACE="${NAMESPACE:-sandbox}"
RELEASE="${RELEASE:-sandbox}"
ENABLE_INGRESS="${ENABLE_INGRESS:-false}"
# Pin to the Kubernetes version whose images are already on this host.
# `stable` would try to pull newer images; the Minikube node cannot reach
# registry.k8s.io through TLS inspection.
MINIKUBE_K8S="${MINIKUBE_K8S:-v1.37.0}"
PF_PORT="${PF_PORT:-18083}"
LOCAL_BIN="${HOME}/.local/bin"
export PATH="${LOCAL_BIN}:/usr/local/bin:/usr/bin:/usr/sbin:/bin"

log() { printf '==> %s\n' "$*"; }

install_minikube() {
  if command -v minikube >/dev/null 2>&1; then
    return
  fi
  log "Installing minikube into ${LOCAL_BIN}"
  mkdir -p "${LOCAL_BIN}"
  curl -fsSL -o /tmp/minikube-linux-amd64 \
    https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
  install -m 0755 /tmp/minikube-linux-amd64 "${LOCAL_BIN}/minikube"
}

install_kubectl() {
  if command -v kubectl >/dev/null 2>&1; then
    return
  fi
  log "Installing kubectl into ${LOCAL_BIN}"
  mkdir -p "${LOCAL_BIN}"
  local ver
  ver="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  curl -fsSL -o /tmp/kubectl "https://dl.k8s.io/release/${ver}/bin/linux/amd64/kubectl"
  install -m 0755 /tmp/kubectl "${LOCAL_BIN}/kubectl"
}

preload_host_images() {
  local img
  while read -r img; do
    [[ -z "${img}" || "${img}" == *"<none>"* ]] && continue
    log "Loading host image ${img} into minikube"
    minikube image load "${img}" --profile="${PROFILE}" || true
  done < <(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E 'kindnetd|pause|coredns|kube-proxy|kube-apiserver|kube-controller-manager|kube-scheduler|etcd|storage-provisioner|ingress-nginx' || true)
}

load_pulling_images() {
  local images image
  images="$(kubectl --context="${CONTEXT}" get pods -A -o jsonpath='{range .items[*]}{range .spec.containers[*]}{.image}{"\n"}{end}{range .spec.initContainers[*]}{.image}{"\n"}{end}{end}' 2>/dev/null | sort -u || true)"
  while read -r image; do
    [[ -z "${image}" ]] && continue
    if docker image inspect "${image}" >/dev/null 2>&1; then
      log "Reloading already-local image ${image}"
    else
      log "Pulling ${image} on the host (node registry access is unreliable behind TLS inspection)"
      docker pull "${image}" || continue
    fi
    minikube image load "${image}" --profile="${PROFILE}" || true
  done <<< "${images}"
}

wait_for_api() {
  local i
  for i in $(seq 1 60); do
    if kubectl --context="${CONTEXT}" get --raw=/readyz >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  return 1
}

wait_for_node() {
  local ready=""
  local i
  for i in $(seq 1 60); do
    ready="$(kubectl --context="${CONTEXT}" get nodes -o jsonpath='{range .items[*]}{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null | head -1 || true)"
    if [[ "${ready}" == "True" ]]; then
      return 0
    fi
    sleep 3
  done
  return 1
}

install_minikube
install_kubectl
command -v helm >/dev/null 2>&1 || { log "helm is required on PATH"; exit 1; }
command -v docker >/dev/null 2>&1 || { log "docker is required on PATH"; exit 1; }

BEFORE_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
log "Starting minikube profile '${PROFILE}' (docker driver, keep existing kube context ${BEFORE_CONTEXT:-none})"
minikube start \
  --profile="${PROFILE}" \
  --driver=docker \
  --keep-context \
  --cpus="${MINIKUBE_CPUS:-2}" \
  --memory="${MINIKUBE_MEMORY:-3072}" \
  --kubernetes-version="${MINIKUBE_K8S}"

# minikube v1.39 can still flip current-context even with --keep-context.
if [[ -n "${BEFORE_CONTEXT}" ]]; then
  kubectl config use-context "${BEFORE_CONTEXT}" >/dev/null
fi
AFTER_CONTEXT="$(kubectl config current-context 2>/dev/null || true)"
if [[ -n "${BEFORE_CONTEXT}" && "${AFTER_CONTEXT}" != "${BEFORE_CONTEXT}" ]]; then
  log "ERROR: failed to restore kube context ${BEFORE_CONTEXT} (now ${AFTER_CONTEXT})"
  exit 1
fi

CONTEXT="${PROFILE}"
log "Using kube-context ${CONTEXT} via explicit flags (current context is ${AFTER_CONTEXT:-none})"

preload_host_images

if ! wait_for_api; then
  log "Kubernetes API on context ${CONTEXT} did not become ready"
  minikube status --profile="${PROFILE}" || true
  exit 1
fi

load_pulling_images
kubectl --context="${CONTEXT}" -n kube-system delete pods -l app=kindnet --wait=false 2>/dev/null || true

if ! wait_for_node; then
  log "Minikube node is not Ready (usually CNI/kindnet image pull). See kube-system pods."
  kubectl --context="${CONTEXT}" get nodes || true
  kubectl --context="${CONTEXT}" -n kube-system get pods -o wide || true
  exit 1
fi

if [[ "${ENABLE_INGRESS}" == "true" ]]; then
  if timeout 45 minikube addons enable ingress --profile="${PROFILE}"; then
    log "Ingress addon enabled"
  else
    log "Ingress addon skipped or timed out; continuing with port-forward"
  fi
else
  log "Ingress addon disabled (set ENABLE_INGRESS=true to try it). Port-forward is the local path."
fi

log "Building ${IMAGE_NAME}:${IMAGE_TAG}"
IMAGE_NAME="${IMAGE_NAME}" IMAGE_TAG="${IMAGE_TAG}" "${ROOT}/scripts/docker-build.sh"

log "Loading application image into minikube"
# containerd (Minikube's default runtime here) often stores short names as docker.io/library/...
if [[ "${IMAGE_NAME}" != */* ]]; then
  docker tag "${IMAGE_NAME}:${IMAGE_TAG}" "docker.io/library/${IMAGE_NAME}:${IMAGE_TAG}" 2>/dev/null || true
fi
minikube image load "${IMAGE_NAME}:${IMAGE_TAG}" --profile="${PROFILE}"
if ! minikube image ls --profile="${PROFILE}" | grep -q "${IMAGE_NAME}:${IMAGE_TAG}"; then
  log "ERROR: ${IMAGE_NAME}:${IMAGE_TAG} is not present in the Minikube node after image load"
  minikube image ls --profile="${PROFILE}" || true
  exit 1
fi

INGRESS_ENABLED=false
INGRESS_CLASS=""
if [[ "${ENABLE_INGRESS}" == "true" ]] && kubectl --context="${CONTEXT}" get ingressclass nginx >/dev/null 2>&1; then
  INGRESS_CLASS="nginx"
  INGRESS_ENABLED=true
fi

log "Installing Helm release ${RELEASE} into ${NAMESPACE}"
if ! helm upgrade --install "${RELEASE}" "${ROOT}/helm" \
  --kube-context "${CONTEXT}" \
  --namespace "${NAMESPACE}" \
  --create-namespace \
  --set image.repository="${IMAGE_NAME}" \
  --set image.tag="${IMAGE_TAG}" \
  --set image.pullPolicy=Never \
  --set environment=dev \
  --set fullnameOverride=confapi \
  --set ingress.enabled="${INGRESS_ENABLED}" \
  --set ingress.className="${INGRESS_CLASS}" \
  --set ingress.host=confapi.local \
  --wait \
  --timeout 3m; then
  log "Helm install failed. Cluster dump:"
  kubectl --context="${CONTEXT}" -n "${NAMESPACE}" get deploy,svc,pods,events -o wide || true
  kubectl --context="${CONTEXT}" -n "${NAMESPACE}" describe pods || true
  exit 1
fi

DEPLOY_NAME="$(kubectl --context="${CONTEXT}" -n "${NAMESPACE}" get deploy \
  -l "app.kubernetes.io/instance=${RELEASE}" \
  -o jsonpath='{.items[0].metadata.name}')"
SVC_NAME="$(kubectl --context="${CONTEXT}" -n "${NAMESPACE}" get svc \
  -l "app.kubernetes.io/instance=${RELEASE}" \
  -o jsonpath='{.items[0].metadata.name}')"
if [[ -z "${DEPLOY_NAME}" || -z "${SVC_NAME}" ]]; then
  log "ERROR: Helm release ${RELEASE} did not create a Deployment/Service in ${NAMESPACE}"
  kubectl --context="${CONTEXT}" -n "${NAMESPACE}" get all || true
  exit 1
fi

kubectl --context="${CONTEXT}" -n "${NAMESPACE}" rollout status "deploy/${DEPLOY_NAME}" --timeout=180s
kubectl --context="${CONTEXT}" -n "${NAMESPACE}" get deploy,svc,pods,ingress

log "Waiting for Endpoints on svc/${SVC_NAME}"
READY_EP=0
for _ in $(seq 1 30); do
  ep="$(kubectl --context="${CONTEXT}" -n "${NAMESPACE}" get endpoints "${SVC_NAME}" -o jsonpath='{.subsets[0].addresses[0].ip}' 2>/dev/null || true)"
  if [[ -n "${ep}" ]]; then
    READY_EP=1
    break
  fi
  sleep 2
done
if [[ "${READY_EP}" != "1" ]]; then
  log "Service ${SVC_NAME} has no Endpoints"
  kubectl --context="${CONTEXT}" -n "${NAMESPACE}" get endpoints,pods,svc -o wide || true
  kubectl --context="${CONTEXT}" -n "${NAMESPACE}" describe "deploy/${DEPLOY_NAME}" || true
  exit 1
fi

log "Port-forwarding svc/${SVC_NAME} to 127.0.0.1:${PF_PORT}"
kubectl --context="${CONTEXT}" -n "${NAMESPACE}" port-forward "svc/${SVC_NAME}" "${PF_PORT}:8080" >/tmp/confapi-port-forward.log 2>&1 &
PF_PID=$!
trap 'kill ${PF_PID} 2>/dev/null || true' EXIT

READY=0
for _ in $(seq 1 30); do
  if curl -sf "http://127.0.0.1:${PF_PORT}/health" >/dev/null; then
    READY=1
    break
  fi
  sleep 1
done
if [[ "${READY}" != "1" ]]; then
  log "Port-forward did not become ready. Log:"
  cat /tmp/confapi-port-forward.log || true
  kubectl --context="${CONTEXT}" -n "${NAMESPACE}" describe "deploy/${DEPLOY_NAME}" || true
  kubectl --context="${CONTEXT}" -n "${NAMESPACE}" get pods -o wide || true
  exit 1
fi

log "Minikube deploy succeeded on context ${CONTEXT} (current kube context still ${AFTER_CONTEXT:-none})"

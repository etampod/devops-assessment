#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p certs
if compgen -G "/usr/local/share/ca-certificates/*.crt" > /dev/null; then
  cp /usr/local/share/ca-certificates/*.crt certs/
fi

docker build -t "${IMAGE_NAME:-confapi}:${IMAGE_TAG:-1.0.0}" .

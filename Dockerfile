FROM alpine:3.22@sha256:5291449c3df73caf6ed85e649dec1b9e818b39a5d8c871e97afc13e9cd5e8fa8

WORKDIR /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    HOME=/tmp \
    PORT=8080 \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    PIP_CERT=/etc/ssl/certs/ca-certificates.crt \
    PATH="/opt/venv/bin:$PATH"

RUN adduser -D -H -u 10001 -s /sbin/nologin appuser \
    && apk add --no-cache python3 py3-pip ca-certificates \
    && python3 -m venv /opt/venv \
    && update-ca-certificates

# Optional extra CAs (corporate TLS inspection). scripts/docker-build.sh copies
# host CAs from /usr/local/share/ca-certificates into certs/ when they exist.
# GitLab can inject EXTRA_CA_CERT the same way. Only *.crt files are trusted.
COPY certs/ /tmp/extra-certs/
RUN set -eu; \
    found=0; \
    for f in /tmp/extra-certs/*.crt; do \
      [ -f "$f" ] || continue; \
      cp "$f" /usr/local/share/ca-certificates/; \
      found=1; \
    done; \
    if [ "$found" = 1 ]; then update-ca-certificates; fi; \
    rm -rf /tmp/extra-certs

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app
RUN chown -R 10001:10001 /opt/venv /app

USER appuser

EXPOSE 8080

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]

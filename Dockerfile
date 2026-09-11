# syntax=docker/dockerfile:1
#
# azure-blob-storage service worker image.
#
# The nullplatform worker bridge dials over gRPC and runs the baked bash
# entrypoint on each package-exec action. This image adds the one tool the
# Azure workflows need that the lean base does not carry — OpenTofu — and
# bakes the service in, so the notification channel needs no cmdline of its own.
#
# Deliberately NO azure-cli. The service resolves its identity from the
# nullplatform cloud-providers provider and lets the azurerm provider
# authenticate from ARM_*, and it never creates the tfstate container (it
# writes a per-service key into a container that already exists). Nothing
# under scripts/azure/ shells out to `az`. bash, jq, np, curl and base64 ship
# in the base.
FROM public.ecr.aws/nullplatform/scopes/worker-bridge:1.0.0

# OpenTofu, pinned. Baking it here is the whole point of the OCI model: on the
# git-clone path do_tofu curls a release tarball into /tmp on every action,
# which puts github.com in the critical path of every create/link and leaves
# the version floating.
#
# Keep TOFU_VERSION in sync with .github/workflows/terraform.yml and with
# do_tofu's fallback — see HANDOFF.md § "Versiones de OpenTofu".
ARG TOFU_VERSION=1.10.10

# TARGETARCH is a BuildKit built-in and is EMPTY under the legacy builder, which
# is what a plain `docker build` uses when buildx is not installed. Falling back
# to uname keeps a local verification build working instead of failing on a
# nonsense URL (".../tofu_1.10.10_linux_.tar.gz" → 404 → "tar: invalid magic").
# CI always goes through buildx, where TARGETARCH is what makes the arm64 image
# get the arm64 binary rather than a silently wrong amd64 one.
ARG TARGETARCH
RUN set -eu; \
    arch="${TARGETARCH:-}"; \
    if [ -z "$arch" ]; then \
      case "$(uname -m)" in \
        x86_64|amd64)  arch=amd64 ;; \
        aarch64|arm64) arch=arm64 ;; \
        *) echo "unsupported architecture: $(uname -m)" >&2; exit 1 ;; \
      esac; \
    fi; \
    # Download to a file rather than piping into tar, so an HTTP error surfaces
    # as curl's own message instead of a confusing tar decompression failure.
    curl -fsSL -o /tmp/tofu.tar.gz \
      "https://github.com/opentofu/opentofu/releases/download/v${TOFU_VERSION}/tofu_${TOFU_VERSION}_linux_${arch}.tar.gz"; \
    tar -xzf /tmp/tofu.tar.gz -C /usr/local/bin tofu; \
    rm -f /tmp/tofu.tar.gz; \
    tofu version

# Bake the service in and point the bridge at its entrypoint + service path.
# NP_SERVICE_PATH must match the `entrypoint` passed to the
# service_definition_agent_association module — see HANDOFF.md.
COPY . /app/pkg
ENV NP_PACKAGE_NAME=azure-blob-storage \
    NP_SERVICE_PATH=/app/pkg/azure-blob-storage \
    NP_SCOPE_ENTRYPOINT=/app/pkg/azure-blob-storage/entrypoint/entrypoint

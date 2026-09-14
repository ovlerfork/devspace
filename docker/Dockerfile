# syntax=docker/dockerfile:1

# DevSpace container image.
#
# The image builds the DevSpace package from the checked-out source and installs
# it into a self-contained prefix, so the runtime image contains exactly the
# same published package that `npm install -g @waishnav/devspace` produces.
#
# The image listens on 0.0.0.0:7676 inside the container. Publish it to the host
# only behind a tunnel you control; loopback publishing is the safe default.

ARG NODE_IMAGE=node:24.16.0-bookworm-slim

FROM ${NODE_IMAGE} AS build

WORKDIR /source

# Native dependencies (better-sqlite3, node-pty) fall back to node-gyp when a
# prebuilt binary is unavailable for the target platform, so keep a toolchain.
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      g++ \
      make \
      python3; \
    rm -rf /var/lib/apt/lists/*; \
    npm install --global pnpm@11.25.0

COPY package.json pnpm-lock.yaml pnpm-workspace.yaml ./
# The root postinstall runs during `pnpm install` and needs its helper script.
COPY scripts ./scripts
RUN --mount=type=cache,id=devspace-pnpm-store,target=/pnpm-store \
    pnpm install --frozen-lockfile --store-dir=/pnpm-store

COPY . .

RUN set -eux; \
    pnpm build; \
    npm pack --ignore-scripts; \
    npm install --global --prefix /opt/devspace ./waishnav-devspace-*.tgz; \
    rm -f ./waishnav-devspace-*.tgz; \
    /opt/devspace/bin/devspace version; \
    node -e "const Database = require('/opt/devspace/lib/node_modules/@waishnav/devspace/node_modules/better-sqlite3'); new Database(':memory:').close(); console.log('better-sqlite3 binding ok');"

FROM ${NODE_IMAGE} AS runtime

ARG DEVSPACE_VERSION=0.0.0
ARG DEVSPACE_UPSTREAM_SHA=unknown
ARG DEVSPACE_SOURCE_SHA=unknown
ARG DEVSPACE_RUNTIME_USER=devspace
ARG DEVSPACE_UID=1000
ARG DEVSPACE_GID=1000

LABEL org.opencontainers.image.title="DevSpace" \
      org.opencontainers.image.description="Self-hosted MCP server for a local coding workspace." \
      org.opencontainers.image.source="https://github.com/Waishnav/devspace" \
      org.opencontainers.image.version="${DEVSPACE_VERSION}" \
      org.opencontainers.image.revision="${DEVSPACE_SOURCE_SHA}" \
      io.ovlerfork.devspace.upstream.revision="${DEVSPACE_UPSTREAM_SHA}"

# Agent CLIs installed at runtime by the entrypoint live in the data volume, so
# put that prefix ahead of the image's own binaries on PATH.
ENV NODE_ENV=production \
    DEVSPACE_CONFIG_DIR=/data/config \
    HOME=/data/home \
    PATH=/data/agents/bin:/opt/devspace/bin:${PATH}

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
      bubblewrap \
      ca-certificates \
      curl \
      git \
      jq \
      less \
      openssh-client \
      procps \
      ripgrep \
      socat \
      tini \
      unzip; \
    rm -rf /var/lib/apt/lists/*

# Official Node images already ship uid/gid 1000 as `node`. Adopt that account
# when it exists so the runtime contract stays `devspace`, and create the
# account when a custom DEVSPACE_UID/GID is requested.
RUN set -eux; \
    mkdir -p /data/home; \
    existing_entry="$(getent passwd "${DEVSPACE_UID}" || true)"; \
    group_entry="$(getent group "${DEVSPACE_GID}" || true)"; \
    if [ -n "${existing_entry}" ]; then \
      usermod --login "${DEVSPACE_RUNTIME_USER}" --home /data/home "${existing_entry%%:*}"; \
    elif [ -z "${group_entry}" ]; then \
      groupadd --gid "${DEVSPACE_GID}" "${DEVSPACE_RUNTIME_USER}"; \
      useradd --uid "${DEVSPACE_UID}" --gid "${DEVSPACE_RUNTIME_USER}" \
        --create-home --home-dir /data/home --shell /bin/bash "${DEVSPACE_RUNTIME_USER}"; \
    else \
      useradd --uid "${DEVSPACE_UID}" --gid "${group_entry%%:*}" \
        --create-home --home-dir /data/home --shell /bin/bash "${DEVSPACE_RUNTIME_USER}"; \
    fi; \
    mkdir -p /workspaces /data/config /data/state /data/worktrees; \
    chown -R "${DEVSPACE_UID}:${DEVSPACE_GID}" /data /workspaces

COPY --from=build /opt/devspace /opt/devspace
COPY docker/entrypoint.sh docker/config-from-env.mjs /usr/local/lib/devspace/
RUN set -eux; \
    chmod 0755 /usr/local/lib/devspace/entrypoint.sh; \
    ln -s /usr/local/lib/devspace/entrypoint.sh /usr/local/bin/devspace-entrypoint

USER ${DEVSPACE_RUNTIME_USER}
WORKDIR /workspaces
VOLUME ["/data"]
EXPOSE 7676

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${PORT:-7676}/healthz" >/dev/null || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/devspace-entrypoint"]
CMD ["serve"]

#!/usr/bin/env bash
# Container entrypoint for DevSpace.
#
# For `serve` it makes sure the container has a usable configuration and owner
# token, then hands the terminal over to the DevSpace CLI. Other commands run
# unchanged so one-off invocations such as `init`, `doctor`, or `version` work
# like an installed CLI.

set -euo pipefail

CONFIG_DIR="${DEVSPACE_CONFIG_DIR:-/data/config}"
CONFIG_PATH="${CONFIG_DIR}/config.jsonc"

log() {
  printf 'devspace-entrypoint: %s\n' "$*" >&2
}

if [[ $# -eq 0 ]]; then
  set -- serve
fi

case "$1" in
  serve | start)
    owner_token="${DEVSPACE_OAUTH_OWNER_TOKEN:-}"
    if [[ -n "${owner_token}" && "${#owner_token}" -lt 16 ]]; then
      log "DEVSPACE_OAUTH_OWNER_TOKEN must be at least 16 characters long."
      exit 1
    fi
    if [[ -z "${owner_token}" && ! -s "${CONFIG_DIR}/auth.json" ]]; then
      log "DevSpace needs an owner token. Set DEVSPACE_OAUTH_OWNER_TOKEN (at least 16 characters),"
      log "or run 'docker run -it ... init' once against the mounted ${CONFIG_DIR} volume."
      exit 1
    fi

    if [[ -n "${DEVSPACE_CONFIG_JSON:-}" ]]; then
      mkdir -p "${CONFIG_DIR}"
      printf '%s\n' "${DEVSPACE_CONFIG_JSON}" >"${CONFIG_PATH}"
      chmod 0600 "${CONFIG_PATH}"
      log "wrote ${CONFIG_PATH} from DEVSPACE_CONFIG_JSON"
    elif [[ ! -f "${CONFIG_PATH}" ]]; then
      mkdir -p "${CONFIG_DIR}"
      node /usr/local/lib/devspace/config-from-env.mjs "${CONFIG_PATH}"
      chmod 0600 "${CONFIG_PATH}"
      log "created ${CONFIG_PATH} from the container environment"
    fi
    ;;
esac

exec devspace "$@"

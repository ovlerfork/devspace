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

AGENT_PREFIX="${DEVSPACE_AGENT_PREFIX:-/data/agents}"
export PATH="${AGENT_PREFIX}/bin:${PATH}"

agent_package() {
  case "$1" in
    codex) printf '%s' "@openai/codex" ;;
    claude) printf '%s' "@anthropic-ai/claude-code" ;;
    copilot) printf '%s' "@github/copilot" ;;
    opencode) printf '%s' "opencode-ai" ;;
    pi) printf '%s' "@earendil-works/pi-coding-agent" ;;
    *) return 1 ;;
  esac
}

# DevSpace talks to claude, opencode, and pi through SDKs that ship in the
# image; command providers such as codex and copilot need a CLI on PATH. These
# installs land in the data volume so they survive container recreation.
install_agents() {
  local requested="${DEVSPACE_AGENTS:-}"
  if [[ -z "${requested//[[:space:],]/}" ]]; then
    return 0
  fi
  if ! command -v npm >/dev/null 2>&1; then
    log "[agents] DEVSPACE_AGENTS is set, but npm is not available in this image"
    return 0
  fi
  mkdir -p "${AGENT_PREFIX}"
  local entry name version package spec
  for entry in ${requested//,/ }; do
    name="${entry%@*}"
    version=""
    if [[ "${entry}" == *@* ]]; then
      version="${entry#*@}"
    fi
    if ! package="$(agent_package "${name}")"; then
      log "[agents] unknown agent ${name}; supported: codex, claude, copilot, opencode, pi"
      continue
    fi
    if command -v "${name}" >/dev/null 2>&1; then
      log "[agents] ${name} is already available at $(command -v "${name}")"
      continue
    fi
    spec="${package}"
    if [[ -n "${version}" ]]; then
      spec="${package}@${version}"
    fi
    log "[agents] installing ${spec} into ${AGENT_PREFIX}"
    if npm install --global --prefix "${AGENT_PREFIX}" --no-fund --no-audit "${spec}"; then
      log "[agents] installed ${name} at $(command -v "${name}")"
    else
      log "[agents] failed to install ${spec}; ${name} stays unavailable"
    fi
  done
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

    # Ask DevSpace for the effective value instead of parsing JSONC here.
    effective_public_base_url="$(DEVSPACE_CONFIG_DIR="${CONFIG_DIR}" devspace config get 2>/dev/null \
      | jq -r '.server.publicBaseUrl // ""' 2>/dev/null || true)"
    if [[ -z "${effective_public_base_url}" ]]; then
      if [[ -n "${DEVSPACE_PUBLIC_BASE_URL:-}" ]]; then
        log "note: ${CONFIG_PATH} exists without server.publicBaseUrl, so DEVSPACE_PUBLIC_BASE_URL is ignored"
        log "      Run: devspace config set publicBaseUrl ${DEVSPACE_PUBLIC_BASE_URL}"
      else
        log "note: server.publicBaseUrl is unset, so OAuth discovery advertises the container-local address"
        log "      Set it to the public URL your MCP clients use, for example https://devspace.example.com"
      fi
    fi

    install_agents
    ;;
esac

exec devspace "$@"

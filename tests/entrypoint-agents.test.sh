#!/usr/bin/env bash
#
# Exercises the container entrypoint's agent installer against the patched
# source without needing Docker. SOURCE_DIR points at a tree with the patch
# series applied (Patch Check passes the checked-out upstream source).
set -euo pipefail

source_dir="${SOURCE_DIR:-../source}"
entrypoint="${DEVSPACE_ENTRYPOINT:-${source_dir}/docker/entrypoint.sh}"
config_bootstrap="${source_dir}/docker/config-from-env.mjs"

if [[ ! -f "${entrypoint}" || ! -f "${config_bootstrap}" ]]; then
  printf 'The container entrypoint was not found under %s.\n' "${source_dir}" >&2
  printf 'Set SOURCE_DIR or DEVSPACE_ENTRYPOINT to a patched source checkout.\n' >&2
  exit 1
fi

work="$(mktemp -d)"
trap 'rm -rf "${work}"' EXIT

mkdir -p "${work}/bin" "${work}/lib"
cp "${config_bootstrap}" "${work}/lib/config-from-env.mjs"
sed "s#/usr/local/lib/devspace/config-from-env.mjs#${work}/lib/config-from-env.mjs#" "${entrypoint}" >"${work}/entrypoint.sh"
chmod +x "${work}/entrypoint.sh"

cat >"${work}/bin/devspace" <<'STUB'
#!/usr/bin/env bash
if [[ "${1:-}" == "config" && "${2:-}" == "get" ]]; then
  printf '{"server":{"publicBaseUrl":null}}\n'
  exit 0
fi
echo "devspace-stub args: $*"
STUB

cat >"${work}/bin/npm" <<STUB
#!/usr/bin/env bash
echo "npm \$*" >> "${work}/npm.log"
if [[ "\${STUB_NPM_FAIL:-}" == "1" ]]; then
  exit 1
fi
spec="\${@: -1}"
case "\$spec" in
  *"/codex"*|*"/codex@"*) bin=codex ;;
  *"pi-coding-agent"*) bin=pi ;;
  *) bin="\${spec##*/}"; bin="\${bin%@*}" ;;
esac
mkdir -p "${work}/prefix/bin"
printf '#!/usr/bin/env bash\necho "%s stub"\n' "\$bin" >"${work}/prefix/bin/\$bin"
chmod +x "${work}/prefix/bin/\$bin"
STUB
chmod +x "${work}/bin/devspace" "${work}/bin/npm"

# Keep the host's own agent CLIs out of the picture.
path="${work}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

run_entrypoint() {
  rm -rf "${work}/data" "${work}/prefix" "${work}/npm.log"
  mkdir -p "${work}/data"
  PATH="${path}" \
    DEVSPACE_CONFIG_DIR="${work}/data/config" \
    DEVSPACE_AGENT_PREFIX="${work}/prefix" \
    DEVSPACE_OAUTH_OWNER_TOKEN=0123456789abcdef \
    "$@" "${work}/entrypoint.sh" serve 2>&1
}

assert_contains() {
  local output="$1"
  local expected="$2"
  local label="$3"
  if [[ "${output}" != *"${expected}"* ]]; then
    printf '%s failed\nexpected to contain: %s\noutput:\n%s\n' "${label}" "${expected}" "${output}" >&2
    exit 1
  fi
}

assert_no_npm() {
  local label="$1"
  if [[ -f "${work}/npm.log" ]]; then
    printf '%s failed: npm was called\n%s\n' "${label}" "$(cat "${work}/npm.log")" >&2
    exit 1
  fi
}

assert_npm_spec() {
  local spec="$1"
  local label="$2"
  if ! grep -Fq -- "--no-fund --no-audit ${spec}" "${work}/npm.log" 2>/dev/null; then
    printf '%s failed: expected npm to install %s, got:\n%s\n' "${label}" "${spec}" "$(cat "${work}/npm.log" 2>/dev/null || echo "(no npm calls)")" >&2
    exit 1
  fi
}

output="$(run_entrypoint env DEVSPACE_AGENTS=)"
assert_contains "${output}" "devspace-stub args: serve" "an unset DEVSPACE_AGENTS still serves"
assert_no_npm "an unset DEVSPACE_AGENTS"

output="$(run_entrypoint env DEVSPACE_AGENTS=codex)"
assert_contains "${output}" "[agents] installed codex" "codex install"
assert_npm_spec "@openai/codex" "codex install"

output="$(run_entrypoint env DEVSPACE_AGENTS='codex@0.154.0')"
assert_npm_spec "@openai/codex@0.154.0" "pinned agent version"

output="$(run_entrypoint env DEVSPACE_AGENTS=not-an-agent)"
assert_contains "${output}" "unknown agent not-an-agent" "unknown agent names are reported"
assert_no_npm "an unknown agent name"

output="$(run_entrypoint env DEVSPACE_AGENTS=codex STUB_NPM_FAIL=1)"
assert_contains "${output}" "[agents] failed to install @openai/codex" "a failed install is reported"
assert_contains "${output}" "devspace-stub args: serve" "a failed install still serves"

mkdir -p "${work}/prefix/bin"
printf '#!/usr/bin/env bash\necho pi\n' >"${work}/prefix/bin/pi"
chmod +x "${work}/prefix/bin/pi"
rm -f "${work}/npm.log"
output="$(PATH="${path}" DEVSPACE_CONFIG_DIR="${work}/data/config" DEVSPACE_AGENT_PREFIX="${work}/prefix" \
  DEVSPACE_OAUTH_OWNER_TOKEN=0123456789abcdef DEVSPACE_AGENTS=pi "${work}/entrypoint.sh" serve 2>&1)"
assert_contains "${output}" "[agents] pi is already available" "installed agents are skipped"
assert_no_npm "an already installed agent"

printf 'entrypoint agent tests passed\n'

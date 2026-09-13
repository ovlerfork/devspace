#!/usr/bin/env bash
set -euo pipefail

policy_file="${POLICY_FILE:-$(dirname "$0")/../.github/workflows/docker-publish-policy.sh}"
source "${policy_file}"

readonly IMAGE_BASE="ghcr.io/example/devspace"
readonly VERSION="1.2.3"
readonly PRE_SANITIZATION_SHA="a1b2c3d"
readonly UPSTREAM_SHA="0123456789abcdef0123456789abcdef01234567"

assert_equals() {
  local expected="$1"
  local actual="$2"
  local name="$3"
  if [[ "${actual}" != "${expected}" ]]; then
    printf '%s failed\nexpected:\n%s\nactual:\n%s\n' "${name}" "${expected}" "${actual}" >&2
    exit 1
  fi
}

assert_equals $'ghcr.io/example/devspace:dev\nghcr.io/example/devspace:dev-0123456789abcdef0123456789abcdef01234567' \
  "$(docker_publish_tags "${IMAGE_BASE}" dev "${VERSION}" "${PRE_SANITIZATION_SHA}" "${UPSTREAM_SHA}")" \
  "dev tags move with the upstream SHA"

assert_equals $'ghcr.io/example/devspace:prerelease\nghcr.io/example/devspace:prerelease-a1b2c3d\nghcr.io/example/devspace:1.2.3\nghcr.io/example/devspace:1.2.3-a1b2c3d' \
  "$(docker_publish_tags "${IMAGE_BASE}" prerelease "${VERSION}" "${PRE_SANITIZATION_SHA}" "${UPSTREAM_SHA}")" \
  "prerelease tags keep the pre-sanitization source SHA and never move latest"

assert_equals $'ghcr.io/example/devspace:latest\nghcr.io/example/devspace:1.2.3\nghcr.io/example/devspace:1.2.3-a1b2c3d' \
  "$(docker_publish_tags "${IMAGE_BASE}" release "${VERSION}" "${PRE_SANITIZATION_SHA}" "${UPSTREAM_SHA}")" \
  "release tags move latest"

if docker_publish_tags "${IMAGE_BASE}" nonsense "${VERSION}" "${PRE_SANITIZATION_SHA}" "${UPSTREAM_SHA}" >/dev/null 2>&1; then
  printf 'unknown publish modes must fail\n' >&2
  exit 1
fi

assert_equals "dev-${UPSTREAM_SHA}" \
  "$(docker_publish_immutable_tag dev "${VERSION}" "${PRE_SANITIZATION_SHA}" "${UPSTREAM_SHA}")" \
  "development immutable tags use the full upstream SHA"
assert_equals "prerelease-${PRE_SANITIZATION_SHA}" \
  "$(docker_publish_immutable_tag prerelease "${VERSION}" "${PRE_SANITIZATION_SHA}" "${UPSTREAM_SHA}")" \
  "prerelease immutable tags use the source identity"
assert_equals "${VERSION}" \
  "$(docker_publish_immutable_tag release "${VERSION}" "${PRE_SANITIZATION_SHA}" "${UPSTREAM_SHA}")" \
  "release immutable tags use the release version"

assert_equals true "$(docker_publish_should_build false false)" "absent immutable tag publishes"
assert_equals false "$(docker_publish_should_build false true)" "present immutable tag skips"
assert_equals true "$(docker_publish_should_build true true)" "manual dispatch forces a rebuild"
assert_equals true "$(docker_publish_should_build true false)" "manual dispatch publishes an absent tag"

fake_bin="$(mktemp -d)"
trap 'rm -rf "${fake_bin}"' EXIT
cat >"${fake_bin}/gh" <<'EOF'
#!/usr/bin/env bash
case "${MOCK_GH_RESULT}" in
  present) printf '1.2.3\ndev-0123456789abcdef0123456789abcdef01234567\n' ;;
  absent) printf 'HTTP 404: Not Found\n' >&2; exit 1 ;;
  failure) printf 'HTTP 401: Bad credentials\n' >&2; exit 1 ;;
esac
EOF
chmod +x "${fake_bin}/gh"
export PATH="${fake_bin}:${PATH}"

export MOCK_GH_RESULT=present
assert_equals $'1.2.3\ndev-0123456789abcdef0123456789abcdef01234567' \
  "$(docker_publish_existing_tags 'users/example/packages/container/devspace/versions')" \
  "existing tags are listed one per line"

export MOCK_GH_RESULT=absent
assert_equals '' \
  "$(docker_publish_existing_tags 'users/example/packages/container/devspace/versions' 2>/dev/null)" \
  "a missing package is an empty tag list"

export MOCK_GH_RESULT=failure
if docker_publish_existing_tags 'users/example/packages/container/devspace/versions' >/dev/null 2>&1; then
  printf 'unexpected gh failures must stop the publish\n' >&2
  exit 1
fi

printf 'docker publish policy tests passed\n'

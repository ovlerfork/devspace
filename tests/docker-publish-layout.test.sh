#!/usr/bin/env bash
set -euo pipefail

workflow_dir="$(dirname "$0")/../.github/workflows"
workflow_file="${WORKFLOW_FILE:-${workflow_dir}/auto-docker-publish.yml}"

assert_contains() {
  local expected="$1"
  if ! grep -Fq "${expected}" "${workflow_file}"; then
    printf 'workflow is missing: %s\n' "${expected}" >&2
    exit 1
  fi
}

assert_not_contains() {
  local unexpected="$1"
  if grep -Fq "${unexpected}" "${workflow_file}"; then
    printf 'workflow must not contain: %s\n' "${unexpected}" >&2
    exit 1
  fi
}

if ! grep -Fq 'name: Auto Docker Publish' "${workflow_file}"; then
  printf 'the publish workflow must keep its name\n' >&2
  exit 1
fi

# Channels and triggers.
assert_contains '          - auto'
assert_contains '          - release'
assert_contains '          - prerelease'
assert_contains '          - dev'
assert_contains '    types: [completed]'
assert_contains 'workflows: ["Patch Check"]'

# The patched branch is the build input, and its source is upstream plus the
# current patch series.
assert_contains 'repository: ${{ env.UPSTREAM_REPOSITORY }}'
assert_contains 'UPSTREAM_REPOSITORY: Waishnav/devspace'
assert_contains 'git am --3way "$patch"'
assert_contains 'PATCHES=(../patchset/patches/cur/*.patch)'
assert_contains 'rm -rf .github/workflows'
assert_contains 'git push our-fork HEAD:refs/heads/patched --force'
assert_contains 'id: source_identity'

# Tag policy lives in one place and manual dispatches force a rebuild.
assert_contains 'source "${GITHUB_WORKSPACE}/patchset/.github/workflows/docker-publish-policy.sh"'
assert_contains 'docker_publish_should_build "${force}" "${immutable_tag_exists}"'
assert_contains 'if [[ "${EVENT_NAME}" == "workflow_dispatch" ]]; then'
assert_contains 'publish_mode=auto'

# Release tags lead the package.json in upstream commits, so the released
# version comes from the resolved tag.
assert_contains 'RELEASE_TAG: ${{ steps.upstream_ref.outputs.release_tag }}'
assert_contains 'version="${RELEASE_TAG#v}"'
assert_contains 'release_tag=${release_tag}'

# The image builds from the patch-owned Dockerfile with version metadata.
assert_contains 'file: source/docker/Dockerfile'
assert_contains 'context: source'
assert_contains 'DEVSPACE_VERSION=${{ steps.meta.outputs.version }}'
assert_contains 'DEVSPACE_SOURCE_SHA=${{ steps.meta.outputs.source_sha }}'
assert_contains 'DEVSPACE_UPSTREAM_SHA=${{ steps.meta.outputs.upstream_sha }}'
assert_contains 'cache-from: type=gha,scope=devspace-image'
assert_contains 'cache-to: type=gha,scope=devspace-image,mode=max'
assert_contains 'platforms: ${{ env.PLATFORMS }}'

# The publish workflow never touches the npm release path.
assert_not_contains 'npm publish'
assert_not_contains 'npm pack'

printf 'docker publish layout tests passed\n'

#!/usr/bin/env bash
#
# Tag and skip policy for the DevSpace container image. Shared by the publish
# workflow and its tests.

docker_publish_tags() {
  local image_base="$1"
  local publish_mode="$2"
  local resolved_version="$3"
  local source_sha="$4"
  local upstream_sha="$5"

  case "${publish_mode}" in
    dev)
      printf '%s\n%s\n' "${image_base}:dev" "${image_base}:dev-${upstream_sha}"
      ;;
    prerelease)
      printf '%s\n%s\n%s\n%s\n' \
        "${image_base}:prerelease" \
        "${image_base}:prerelease-${source_sha}" \
        "${image_base}:${resolved_version}" \
        "${image_base}:${resolved_version}-${source_sha}"
      ;;
    release)
      printf '%s\n%s\n%s\n' \
        "${image_base}:latest" \
        "${image_base}:${resolved_version}" \
        "${image_base}:${resolved_version}-${source_sha}"
      ;;
    *)
      printf 'unknown publish mode: %s\n' "${publish_mode}" >&2
      return 1
      ;;
  esac
}

docker_publish_immutable_tag() {
  local publish_mode="$1"
  local resolved_version="$2"
  local source_sha="$3"
  local upstream_sha="$4"

  case "${publish_mode}" in
    dev)
      printf 'dev-%s\n' "${upstream_sha}"
      ;;
    prerelease)
      printf 'prerelease-%s\n' "${source_sha}"
      ;;
    release)
      printf '%s\n' "${resolved_version}"
      ;;
    *)
      printf 'unknown publish mode: %s\n' "${publish_mode}" >&2
      return 1
      ;;
  esac
}

# Manual dispatches force a rebuild; scheduled and patch-check runs skip work
# whose immutable tag already exists.
docker_publish_should_build() {
  local force="$1"
  local immutable_tag_exists="$2"

  if [[ "${force}" == "true" ]]; then
    printf 'true\n'
  elif [[ "${immutable_tag_exists}" == "true" ]]; then
    printf 'false\n'
  else
    printf 'true\n'
  fi
}

docker_publish_existing_tags() {
  local package_path="$1"
  local tags_file
  local error_file
  local result

  tags_file="$(mktemp)"
  error_file="$(mktemp)"
  if gh api "${package_path}" --paginate --jq '.[] | .metadata.container.tags[]?' >"${tags_file}" 2>"${error_file}"; then
    cat "${tags_file}"
    result=0
  elif grep -Eq 'HTTP 404|status 404' "${error_file}"; then
    echo "The devspace container package does not exist yet." >&2
    result=0
  else
    cat "${error_file}" >&2
    result=1
  fi

  rm -f "${tags_file}" "${error_file}"
  return "${result}"
}

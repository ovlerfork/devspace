# DevSpace patchset

This repository is maintained as a patch-based fork of `Waishnav/devspace`.

Upstream is treated as read-only. Local changes are stored as replayable patch
files in `patches/cur` and applied with `git am --3way`. The default branch
contains only patchset metadata, and the buildable source lives on the generated
`patched` branch.

## Branches

| Branch | Purpose | Writer |
| --- | --- | --- |
| `patchset` | Patch files, scripts, workflows, and docs. This is the default branch. | Humans |
| `main` | Tracks upstream `Waishnav/devspace` `main`. | CI / maintainers |
| `patched` | Generated branch: upstream plus patches applied, with upstream workflow files dropped. | CI / maintainers |

## Current patch series

- `0001-feat-docker-add-container-image-and-entrypoint.patch` adds a container
  image for the MCP server. It builds the published package from source in a
  multi-stage Dockerfile, installs it into a self-contained prefix, and carries
  a container entrypoint plus `config-from-env.mjs` so a deployment can be
  configured with environment variables instead of a hand-written
  `config.jsonc`. The runtime image runs as a non-root user, keeps
  `/data` as a volume, ships `git`, `ripgrep`, `bubblewrap`, and `socat`, and
  exposes `7676` with a `/healthz` check.
- `0002-docs-docker-document-container-deployment.patch` adds
  `docker/README.md`, `docker/compose.yaml`, `docker/compose.tunnel.yaml`, and
  `docker/env.example` describing tags, configuration, volumes, permissions,
  the container OAuth flow, and tunnel expectations.
- `0003-feat-docker-mount-a-real-config.jsonc-in-the-compose.patch` makes the
  durable `config.jsonc` first-class in the compose examples: the host config
  directory is mounted at `/data/config`, `docker/config.example.jsonc` is a
  commented starting point, and the entrypoint reports when
  `server.publicBaseUrl` is missing or ignored by an existing file.
- `0004-feat-docker-install-agent-CLIs-on-request.patch` installs
  command-provider agent CLIs (`codex`, `claude`, `copilot`, `opencode`, `pi`)
  into the data volume when `DEVSPACE_AGENTS` asks for them, puts that prefix on
  `PATH` ahead of the image binaries, and leaves SDK-backed providers untouched.

The series contains no upstream source behavior changes yet; the patches only
add `docker/` plus `.dockerignore` to the upstream tree.

## Container image

`Auto Docker Publish` builds `ghcr.io/<fork-owner>/devspace` from the patched
source and publishes:

| Tag | Source |
| --- | --- |
| `latest` | Newest published upstream release. While upstream is on a prerelease line, that release is a prerelease. |
| `<version>`, `<version>-<source-sha>` | Upstream release, tagged with the patched source revision. |
| `prerelease`, `prerelease-<source-sha>` | Newest published prerelease. |
| `dev`, `dev-<upstream-sha>` | Upstream `main` plus the current patches. |

Scheduled runs resolve the newest published upstream release and move `latest`
along with the `prerelease` or release version tags. Manual dispatches choose a
channel and always rebuild. The image documentation is in `docker/README.md` on
the `patched` branch.

## Apply locally

```bash
git clone https://github.com/Waishnav/devspace.git devspace-source
cd devspace-source
git remote add upstream https://github.com/Waishnav/devspace.git
git fetch upstream main
PATCH_DIR=/path/to/patchset/patches/cur /path/to/patchset/scripts/apply-patches.sh
```

## Refresh patches

From a branch containing upstream plus local patch commits:

```bash
UPSTREAM_REF=upstream/main /path/to/patchset/scripts/refresh-patches.sh
```

To add patches later, create a branch from the upstream ref, make the local
commits there, and run `scripts/refresh-patches.sh` with `UPSTREAM_REF`
pointing at the same upstream base. Keep each patch focused on one current
fork-only change.

## Automation

- `Upstream Sync` keeps `main` aligned to upstream `Waishnav/devspace:main` and
  drops upstream workflow files from the synced commit. After a real update it
  dispatches `Patch Check` with the exact upstream SHA and development
  publishing enabled.
- `Patch Check` verifies that `patches/cur` applies cleanly to the tested
  upstream ref, runs the patchset metadata sanitizer, validates the shell
  scripts, and runs the publish-policy tests. It uploads conflict artifacts when
  a patch no longer applies.
- `Auto Docker Publish` applies the patch series, updates the `patched` branch,
  and builds `linux/amd64` and `linux/arm64` images from
  `docker/Dockerfile`. Scheduled and patch-check runs skip work whose immutable
  tag already exists; manual dispatches rebuild. Release images take their
  version from the upstream release tag because upstream sets the published
  version at publish time. A release whose tree predates the container source
  layout (no `pnpm-workspace.yaml`) is skipped with a warning instead of
  producing an image the entrypoint cannot configure.

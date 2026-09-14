# Running DevSpace in Docker

The DevSpace image runs the MCP server on a machine that does not have Node
installed, or keeps it in a container next to the projects you want to expose.
It serves the same `/mcp` endpoint as a local install; only the way it is
configured differs.

Shell commands executed through DevSpace run with the container user's
authority inside the container. The image is a packaging and isolation boundary
for the server process, not a sandbox for the mounted projects.

## Quick start

```bash
mkdir -p ./devspace/config
cp docker/config.example.jsonc ./devspace/config/config.jsonc
$EDITOR ./devspace/config/config.jsonc   # set server.publicBaseUrl for your tunnel

docker run -d --name devspace \
  --restart unless-stopped \
  -p 127.0.0.1:7676:7676 \
  -e DEVSPACE_OAUTH_OWNER_TOKEN="$(openssl rand -hex 32)" \
  -v devspace-data:/data \
  -v "$PWD/devspace/config:/data/config" \
  -v /home/me/projects:/workspaces \
  ghcr.io/ovlerfork/devspace:latest
```

`:latest` tracks the newest published upstream release, which is the
`1.1.0-beta` line until upstream tags a stable release from the current source
layout. `:prerelease` names that prerelease explicitly and `:dev` tracks
upstream `main` plus this fork's patches.

Then expose `127.0.0.1:7676` through a tunnel you control and point the MCP
client at `https://devspace.example.com/mcp`. Tunnel lifecycle and credentials
stay with you; the container only serves HTTP.

`server.publicBaseUrl` is the one setting a tunnel deployment must get right:
DevSpace derives the inbound `Host` allowlist and its OAuth issuer from it, and
the entrypoint logs a note when it is missing.

Check that the server is up:

```bash
curl -fsS http://127.0.0.1:7676/healthz
docker logs devspace
```

## Compose

Two examples ship with the image:

| File | Use |
| --- | --- |
| `docker/compose.yaml` | The server alone. It publishes loopback, and your own tunnel forwards to it. |
| `docker/compose.tunnel.yaml` | The server plus a Cloudflare Tunnel sidecar. Nothing is published on the host. |

Copy `docker/env.example` to `docker/.env` so the values live next to the
compose file (Compose reads that file automatically), then:

```bash
mkdir -p docker/config
cp docker/config.example.jsonc docker/config/config.jsonc
$EDITOR docker/config/config.jsonc   # set server.publicBaseUrl for your tunnel
openssl rand -hex 32                 # put the result in DEVSPACE_OAUTH_OWNER_TOKEN
docker compose -f docker/compose.yaml up -d
```

The tunnel variant needs its own token and a public hostname whose origin is
`http://devspace:7676`. Create and own that tunnel in your Cloudflare account;
DevSpace only serves HTTP on the compose network:

```bash
docker compose -f docker/compose.tunnel.yaml up -d
```

## Connecting an MCP client

DevSpace authenticates clients with OAuth, so the container has to know the URL
clients actually use:

- Point clients at the `/mcp` path of the public URL, for example
  `https://devspace.example.com/mcp`.
- Set `server.publicBaseUrl` in `config.jsonc` to that same public URL (or
  `DEVSPACE_PUBLIC_BASE_URL` before the first start). It is the OAuth issuer,
  so a mismatch leaves clients discovering `http://127.0.0.1:7676/...` and
  reporting that the server does not implement OAuth.
- The first connection opens an Owner password approval page. Enter the value of
  `DEVSPACE_OAUTH_OWNER_TOKEN`.
- Registered clients and issued tokens live under `/data`, so they survive
  container restarts.

The unauthenticated `401` for `/mcp` advertises
`https://<public-host>/.well-known/oauth-protected-resource/mcp` in its
`WWW-Authenticate` header, which is where a spec-following client starts
discovery. Check it directly when a client reports that the server does not
implement OAuth:

```bash
curl -si https://devspace.example.com/mcp | grep -i www-authenticate
```

Clients other than ChatGPT may finish the flow on a redirect host that is not
allowed by default. Add it with `DEVSPACE_OAUTH_ALLOWED_REDIRECT_HOSTS`; the
default list is `chatgpt.com,localhost,127.0.0.1`.

## Subagents and agent CLIs

DevSpace can delegate work to local coding agents. The container splits them in
two:

| Provider | Needs | Notes |
| --- | --- | --- |
| `claude`, `opencode`, `pi` | nothing | DevSpace talks to the SDKs shipped in the image. |
| `codex`, `copilot` | a CLI on `PATH` | Install it with `DEVSPACE_AGENTS`. |

`DEVSPACE_AGENTS` installs those CLIs into `/data/agents` on start and puts the
prefix on `PATH`, so they survive container recreation and image updates:

```bash
DEVSPACE_AGENTS=codex docker compose -f docker/compose.yaml up -d
DEVSPACE_AGENTS=codex@0.154.0,copilot docker compose -f docker/compose.yaml up -d
```

Restarts skip agents that are already installed. Remove `/data/agents` from the
volume to force a reinstall or to move a floating version forward. Credentials
live under `HOME` (`/data/home`), so sign in once:

```bash
docker compose exec -it devspace codex login
```

DevSpace only delegates to providers enabled in `config.jsonc`:

```jsonc
"subagents": {
  "enabled": true,
  "providers": [{ "id": "codex", "enabled": true }]
}
```

The image installs no agent by default. Unknown names in `DEVSPACE_AGENTS` are
reported and skipped, and a failed install leaves the server running with that
provider unavailable.

## Image tags

| Tag | Source |
| --- | --- |
| `latest` | Newest published upstream release. While upstream is on a prerelease line, this is that prerelease. |
| `<version>` | Upstream release version, for example `1.1.0-beta.3`. |
| `<version>-<source-sha>` | Immutable build of a patched source revision. |
| `prerelease`, `prerelease-<sha>` | Newest published upstream prerelease. |
| `dev`, `dev-<upstream-sha>` | Upstream `main` plus this fork's patches. |

Upstream tags its releases before the released version reaches `package.json`,
so image versions come from the release tag. Releases whose tree predates the
container source layout (no `pnpm-workspace.yaml`, for example `v1.0.8`) are
skipped: they have no image and never become `latest`.

Images are published for `linux/amd64` and `linux/arm64`. Releases built by the
fork carry the upstream source revision and this fork's revision as image
labels.

## Configuration

DevSpace reads one durable configuration document, `config.jsonc`, from
`${DEVSPACE_CONFIG_DIR}` (`/data/config` in the image). It accepts comments and
trailing commas, is validated before the server starts, and is edited by
`devspace config set` without losing comments. The owner secret is kept out of
it: pass `DEVSPACE_OAUTH_OWNER_TOKEN` or let `devspace init` write `auth.json`
next to the file.

The compose examples mount a host directory at `/data/config`. Start from the
commented example:

```bash
mkdir -p docker/config
cp docker/config.example.jsonc docker/config/config.jsonc
$EDITOR docker/config/config.jsonc   # set server.publicBaseUrl for tunnels
```

Skills and agent profiles placed in that directory persist with it. Change one
value without leaving Docker:

```bash
docker compose exec devspace devspace config set publicBaseUrl https://devspace.example.com
```

The environment variables below are a convenience for deployments that prefer
them: the entrypoint writes `config.jsonc` from the environment only when the
file does not exist yet, so a mounted or edited file always wins.

Container-only variables that never reach `config.jsonc`:

| Variable | Purpose |
| --- | --- |
| `DEVSPACE_CONFIG_JSON` | Replaces `config.jsonc` on every start. |
| `DEVSPACE_AGENTS` | Command-provider CLIs to install into `/data/agents` on start. |
| `DEVSPACE_AGENT_PREFIX` | Install prefix for those CLIs; defaults to `/data/agents`. |

| Variable | Config key | Default |
| --- | --- | --- |
| `DEVSPACE_OAUTH_OWNER_TOKEN` | Owner secret (read from the environment, not stored) | required |
| `HOST` | `server.host` | `0.0.0.0` |
| `PORT` | `server.port` | `7676` |
| `DEVSPACE_PUBLIC_BASE_URL` | `server.publicBaseUrl` | unset |
| `DEVSPACE_ALLOWED_HOSTS` | `server.allowedHosts` | empty |
| `DEVSPACE_TRUST_PROXY` | `server.trustProxy` | `false` |
| `DEVSPACE_ALLOWED_ROOTS` | `workspaces.allowedRoots` | `/workspaces` |
| `DEVSPACE_WORKTREE_ROOT` | `workspaces.worktreeRoot` | `/data/worktrees` |
| `DEVSPACE_STATE_DIR` | `storage.stateDir` | `/data/state` |
| `DEVSPACE_TOOL_MODE` | `tools.mode` | DevSpace default (`codex`) |
| `DEVSPACE_WIDGETS` | `ui.enabled` | DevSpace default |
| `DEVSPACE_ARTIFACTS` | `artifacts.enabled` | DevSpace default |
| `DEVSPACE_ARTIFACT_MAX_FILE_BYTES` | `artifacts.maxFileBytes` | DevSpace default |
| `DEVSPACE_SKILLS` | `skills.enabled` | DevSpace default |
| `DEVSPACE_SKILL_PATHS` | `skills.paths` | DevSpace default |
| `DEVSPACE_AGENT_DIR` | `skills.agentDir` | DevSpace default |
| `DEVSPACE_SUBAGENTS` | `subagents.enabled` | DevSpace default |
| `DEVSPACE_LOG_LEVEL` | `logging.level` | DevSpace default |
| `DEVSPACE_LOG_FORMAT` | `logging.format` | DevSpace default |
| `DEVSPACE_LOG_REQUESTS` | `logging.requests` | DevSpace default |
| `DEVSPACE_LOG_ASSETS` | `logging.assets` | DevSpace default |
| `DEVSPACE_LOG_TOOL_CALLS` | `logging.toolCalls` | DevSpace default |
| `DEVSPACE_LOG_SHELL_COMMANDS` | `logging.shellCommands` | DevSpace default |
| `DEVSPACE_OAUTH_ACCESS_TOKEN_TTL_SECONDS` | `oauth.accessTokenTtlSeconds` | DevSpace default |
| `DEVSPACE_OAUTH_REFRESH_TOKEN_TTL_SECONDS` | `oauth.refreshTokenTtlSeconds` | DevSpace default |
| `DEVSPACE_OAUTH_SCOPES` | `oauth.scopes` | DevSpace default |
| `DEVSPACE_OAUTH_ALLOWED_REDIRECT_HOSTS` | `oauth.allowedRedirectHosts` | DevSpace default |

List values accept commas or newlines. Boolean values accept `1`, `true`,
`yes`, `on` and `0`, `false`, `no`, `off`.

Two escape hatches replace the generated file:

- `DEVSPACE_CONFIG_JSON` is written to `config.jsonc` on every start. Use it
  when you want the deployment to stay declarative.
- Mount your own `config.jsonc` into `${DEVSPACE_CONFIG_DIR}` and the
  entrypoint leaves it alone.

Everything DevSpace persists lives under `/data`: `config.jsonc`, agent state,
and Git worktrees. `HOME` is `/data/home`, so credentials written by local agent
CLIs that you install into the container also survive a restart.

## Permissions

The image serves as `devspace` (uid/gid `1000`). Mounted projects must be
writable by that account, or you can run the container as the owner of the
files:

```bash
docker run --user "$(id -u):$(id -g)" ...
```

A bind-mounted `config.jsonc` still has to be readable by that user. Named
volumes inherit ownership from the image on first use.

## Commands

The entrypoint forwards arguments to the DevSpace CLI, so the image also works
as a one-off client:

```bash
docker run --rm -v devspace-data:/data ghcr.io/ovlerfork/devspace:latest doctor
docker run --rm -it -v devspace-data:/data ghcr.io/ovlerfork/devspace:latest init
```

`init` is interactive and is an alternative to the environment-driven setup. It
writes `config.jsonc` and `auth.json` into the volume, after which `serve` only
needs the same volume mounted.

## Building locally

```bash
docker build -f docker/Dockerfile -t devspace:local .
```

## Updating

```bash
docker pull ghcr.io/ovlerfork/devspace:latest
docker compose -f docker/compose.yaml up -d
```

The configuration schema is versioned. If a later DevSpace version reports a
configuration error, remove `config.jsonc` from the volume and let the
entrypoint regenerate it from the environment.

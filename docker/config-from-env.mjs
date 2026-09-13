#!/usr/bin/env node
// Container configuration bridge.
//
// DevSpace reads its durable configuration from `config.jsonc`; this script
// translates the container-native environment variables documented in
// `docker/README.md` into that file. Only values the operator actually set are
// written, so DevSpace schema defaults still apply to everything else.

import { chmodSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";

const target = process.argv[2];
if (!target) {
  console.error("usage: config-from-env.mjs <config.jsonc path>");
  process.exit(2);
}

const env = process.env;

function text(name) {
  const value = env[name]?.trim();
  return value ? value : undefined;
}

function bool(name) {
  const value = text(name)?.toLowerCase();
  if (value === undefined) return undefined;
  if (["1", "true", "yes", "on", "changes", "full"].includes(value)) return true;
  if (["0", "false", "no", "off"].includes(value)) return false;
  throw new Error(`${name} must be a boolean-like value, got "${env[name]}"`);
}

function integer(name) {
  const value = text(name);
  if (value === undefined) return undefined;
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed)) {
    throw new Error(`${name} must be an integer, got "${env[name]}"`);
  }
  return parsed;
}

function list(name) {
  const value = text(name);
  if (value === undefined) return undefined;
  return value.split(/[,\n]/).map((entry) => entry.trim()).filter(Boolean);
}

function assign(object, key, value) {
  if (value !== undefined) object[key] = value;
}

const server = {
  host: text("HOST") ?? "0.0.0.0",
  port: integer("PORT") ?? 7676,
};
assign(server, "publicBaseUrl", text("DEVSPACE_PUBLIC_BASE_URL") ?? null);
assign(server, "allowedHosts", list("DEVSPACE_ALLOWED_HOSTS"));
assign(server, "trustProxy", bool("DEVSPACE_TRUST_PROXY"));

const allowedRoots = list("DEVSPACE_ALLOWED_ROOTS");
const workspaces = {
  allowedRoots: allowedRoots && allowedRoots.length > 0 ? allowedRoots : ["/workspaces"],
  worktreeRoot: text("DEVSPACE_WORKTREE_ROOT") ?? "/data/worktrees",
};

const storage = {
  stateDir: text("DEVSPACE_STATE_DIR") ?? "/data/state",
};

const tools = {};
assign(tools, "mode", text("DEVSPACE_TOOL_MODE"));

const ui = {};
assign(ui, "enabled", bool("DEVSPACE_WIDGETS"));

const artifacts = {};
assign(artifacts, "enabled", bool("DEVSPACE_ARTIFACTS"));
assign(artifacts, "maxFileBytes", integer("DEVSPACE_ARTIFACT_MAX_FILE_BYTES"));

const skills = {};
assign(skills, "enabled", bool("DEVSPACE_SKILLS"));
assign(skills, "paths", list("DEVSPACE_SKILL_PATHS"));
assign(skills, "agentDir", text("DEVSPACE_AGENT_DIR"));

const subagents = {};
if (bool("DEVSPACE_SUBAGENTS") !== undefined) {
  // Provider definitions live in config.jsonc; the container variable only
  // toggles the feature.
  subagents.enabled = bool("DEVSPACE_SUBAGENTS");
  subagents.providers = [];
}

const logging = {};
assign(logging, "level", text("DEVSPACE_LOG_LEVEL"));
assign(logging, "format", text("DEVSPACE_LOG_FORMAT"));
assign(logging, "requests", bool("DEVSPACE_LOG_REQUESTS"));
assign(logging, "assets", bool("DEVSPACE_LOG_ASSETS"));
assign(logging, "toolCalls", bool("DEVSPACE_LOG_TOOL_CALLS"));
assign(logging, "shellCommands", bool("DEVSPACE_LOG_SHELL_COMMANDS"));

const oauth = {};
assign(oauth, "accessTokenTtlSeconds", integer("DEVSPACE_OAUTH_ACCESS_TOKEN_TTL_SECONDS"));
assign(oauth, "refreshTokenTtlSeconds", integer("DEVSPACE_OAUTH_REFRESH_TOKEN_TTL_SECONDS"));
assign(oauth, "scopes", list("DEVSPACE_OAUTH_SCOPES"));
assign(oauth, "allowedRedirectHosts", list("DEVSPACE_OAUTH_ALLOWED_REDIRECT_HOSTS"));

const config = {
  configVersion: 1,
  server,
  workspaces,
  storage,
};

if (Object.keys(tools).length > 0) config.tools = tools;
if (Object.keys(ui).length > 0) config.ui = ui;
if (Object.keys(artifacts).length > 0) config.artifacts = artifacts;
if (Object.keys(skills).length > 0) config.skills = skills;
if (Object.keys(subagents).length > 0) config.subagents = subagents;
if (Object.keys(logging).length > 0) config.logging = logging;
if (Object.keys(oauth).length > 0) config.oauth = oauth;

mkdirSync(dirname(target), { recursive: true });
writeFileSync(target, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });
chmodSync(target, 0o600);
console.log(`devspace-entrypoint: wrote ${target}`);

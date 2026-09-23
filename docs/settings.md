# Settings precedence in the sandbox

Highest first:

1. **`/etc/claude-code/managed-settings.json`** — baked into the image,
   root-owned, mode 0444. Outside the workspace and outside the auth volume, so
   neither a mounted repo nor the agent can reach it. Hard guardrails only.
2. **`/etc/claude-code/managed-settings.d/*.json`** — drop-ins merged after the
   main file. `--offline` mounts `90-untrusted.json` here.
3. **Project `.claude/settings.local.json` and `.claude/settings.json`** — from
   the bind-mounted repo. These work exactly as they do on the host, which is
   deliberate.
4. **`$CLAUDE_CONFIG_DIR/settings.json`** — seeded once on first run, then
   yours to edit. Lives in the auth volume.

## Use `Edit(path)`, never `Write(path)`

A `Write(path)` deny rule is **not matched by file permission checks**. Only
`Edit(path)` rules are, and an `Edit` rule covers every file-editing tool,
including Write. The CLI prints a warning per offending rule at startup and the
rule then silently protects nothing.

This bit the base policy: `.mcp.json` and both project settings files were
listed only as `Write(...)`, so they were unprotected until it was fixed.
`make smoke` now fails if any `Write(path)` rule reappears in the deny list, and
asserts each expected `Edit(...)` rule is present.

## Two keys deliberately left unset

Anthropic's worked example of a managed settings file includes two keys that
would quietly break this design. The base policy must not copy it wholesale, and
`make smoke` asserts both stay unset:

- **`permissions.disableBypassPermissionsMode`** turns off skip-permissions
  mode entirely. Setting it makes `--yolo` fail with a confusing error rather
  than work.
- **`allowManagedPermissionRulesOnly`** makes the agent ignore permission rules
  from user, project and local files. Setting it means a repo's own
  `.claude/settings.json` stops having any effect.

Both ship in `base/profiles/untrusted.json` instead, applied only by
`--offline`, where disabling bypass mode is exactly what you want.

## Why the host configuration is not mounted

`~/.claude/settings.json` on this Mac hardcodes `/Users/glen/...` paths across
nine hooks and a status line, and an nvm Node interpreter that does not exist in
the container. Mounting it would break all of them. The config directory is also
345 MB, mostly skills and backups.

The container gets a minimal seeded settings file instead, and the guardrails
live in managed settings where a repo cannot override them.

The entrypoint greps a project's own settings for host-absolute paths and warns
once at startup, because several repos here have them and the resulting failures
are otherwise mysterious.

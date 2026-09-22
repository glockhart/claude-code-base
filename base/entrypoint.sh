#!/usr/bin/env bash
# Entrypoint for claude-code-base.
#
# Two supported invocations, chosen by the launcher:
#
#   Profile A - started as uid 1000. macOS (Docker Desktop virtualises bind-mount
#     ownership) or a Linux host that already is 1000:1000. Nothing to remap, so
#     the container never holds root at all.
#
#   Profile B - started as uid 0 with HOST_UID/HOST_GID set. Native Linux where
#     the host identity is not 1000:1000. Renumber the claude user, fix the
#     volumes we own, then drop with gosu.
#
# Profile B needs CAP_CHOWN CAP_SETUID CAP_SETGID CAP_FOWNER CAP_DAC_OVERRIDE on
# top of --cap-drop ALL. Those are cleared on the identity change, so the agent
# never holds them. gosu is not setuid, so no-new-privileges does not block it.
set -euo pipefail

SANDBOX_USER=claude
SANDBOX_HOME=/home/claude
: "${CLAUDE_CONFIG_DIR:=$SANDBOX_HOME/.claude}"
export CLAUDE_CONFIG_DIR HOME="$SANDBOX_HOME"

log()  { printf '\033[2m[sandbox]\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[33m[sandbox]\033[0m %s\n' "$*" >&2; }

# ---------------------------------------------------------------- identity ---
remap_identity() {
  local want_uid=$1 want_gid=$2 have_uid have_gid owner
  have_uid=$(id -u "$SANDBOX_USER"); have_gid=$(id -g "$SANDBOX_USER")

  if [ "$want_gid" != "$have_gid" ]; then
    owner=$(getent group "$want_gid" | cut -d: -f1 || true)
    if [ -n "$owner" ]; then
      # The gid already belongs to a system group. macOS gid 20 collides with
      # Debian's 'dialout', so join it rather than renumbering it away.
      log "gid $want_gid is already '$owner'; joining it instead of renumbering"
      usermod -g "$want_gid" "$SANDBOX_USER"
    else
      groupmod -g "$want_gid" "$SANDBOX_USER"
    fi
  fi

  if [ "$want_uid" != "$have_uid" ]; then
    owner=$(getent passwd "$want_uid" | cut -d: -f1 || true)
    if [ -n "$owner" ] && [ "$owner" != "$SANDBOX_USER" ]; then
      warn "uid $want_uid already belongs to '$owner'; cannot remap."
      warn "set SANDBOX_SKIP_UID_REMAP=1 to continue with uid $have_uid instead."
      exit 78   # EX_CONFIG
    fi
    usermod -u "$want_uid" "$SANDBOX_USER"
  fi
}

# groupmod does not re-chgrp anything, and named volumes under $HOME were seeded
# with the image's ownership. Fix only the mountpoints we own. The workspace
# bind mount is NEVER touched: a recursive chown of someone's repository is both
# slow and destructive, and under both profiles the ownership is already right.
fix_volume_ownership() {
  local want="$1:$2" d
  for d in "$CLAUDE_CONFIG_DIR" "$CLAUDE_CONFIG_DIR/projects" "$CLAUDE_CONFIG_DIR/ide" \
           "$SANDBOX_HOME/.cache" "$SANDBOX_HOME/.config" "$SANDBOX_HOME/.local"; do
    [ -d "$d" ] || continue
    if [ "$(stat -c '%u:%g' "$d")" != "$want" ]; then
      log "chown -R $want $d"
      chown -R "$want" "$d"
    fi
  done
}

# ------------------------------------------------------------- first run -----
seed_config() {
  mkdir -p "$CLAUDE_CONFIG_DIR" "$CLAUDE_CONFIG_DIR/ide"
  # Intentionally minimal. The hard guardrails live in managed settings, which
  # sit outside this volume at /etc/claude-code/ and outrank everything here.
  if [ ! -f "$CLAUDE_CONFIG_DIR/settings.json" ]; then
    log "seeding $CLAUDE_CONFIG_DIR/settings.json"
    printf '{\n  "includeCoAuthoredBy": false\n}\n' > "$CLAUDE_CONFIG_DIR/settings.json"
  fi
}

mark_workspace_safe() {
  # git refuses to operate on a repo owned by another uid. Under profile A the
  # virtualised ownership can still trip this.
  git config --global --replace-all safe.directory '/workspace' 2>/dev/null || true
  git config --global --add safe.directory '*' 2>/dev/null || true
}

# The single most confusing failure mode: a repo's own .claude/settings.json
# referencing host-absolute paths or the host's nvm node. Turn it into one clear
# line at startup instead of a mystery later.
check_project_settings() {
  local f
  for f in .claude/settings.json .claude/settings.local.json; do
    [ -f "$f" ] || continue
    if grep -qE '"/Users/|/\.nvm/|/home/[a-z]+/' "$f" 2>/dev/null; then
      warn "$f references host paths that do not exist in this container."
      warn "  its hooks and statusline will fail. See docs/settings.md"
    fi
  done
}

# ------------------------------------------------------------------ exec -----
[ "$#" -gt 0 ] || set -- claude

if [ "$(id -u)" -eq 0 ]; then
  if [ "${SANDBOX_SKIP_UID_REMAP:-0}" != 1 ] && [ -n "${HOST_UID:-}" ] && [ -n "${HOST_GID:-}" ]; then
    remap_identity "$HOST_UID" "$HOST_GID"
    fix_volume_ownership "$(id -u "$SANDBOX_USER")" "$(id -g "$SANDBOX_USER")"
  fi
  # Re-enter as the unprivileged user so seeding creates files owned correctly.
  exec gosu "$SANDBOX_USER" "$0" --dropped "$@"
fi

[ "${1-}" = "--dropped" ] && shift

sandbox-preflight || exit $?
seed_config
mark_workspace_safe
check_project_settings

exec "$@"

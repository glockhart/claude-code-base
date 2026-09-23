#!/usr/bin/env bash
# shellcheck disable=SC2015  # `cond && pass || fail` is deliberate; both return 0
# shellcheck source=/dev/null
# Checks that need only the built image. No proxy, no network.
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/lib.sh"; set -a; . "$ROOT/versions.env"; set +a
need_docker
IMG=$BASE_IMAGE_NAME:$CLAUDE_CODE_VERSION
run() { docker run --rm --entrypoint bash "$IMG" -c "$1" 2>/dev/null; }

head_ "1. No secrets in the image"
env_dump=$(docker run --rm --entrypoint /usr/bin/env "$IMG" 2>/dev/null)
grep -qEi '(api|secret|token|password)_?key?=' <<<"$env_dump" \
  && fail "credential-shaped variable in image env" || pass "image env is clean"
docker history --no-trunc --format '{{.CreatedBy}}' "$IMG" 2>/dev/null \
  | grep -qEi 'sk-ant-|ghp_|ANTHROPIC_API_KEY|GITHUB_TOKEN' \
  && fail "credential material in build history" || pass "build history is clean"
run 'test -e /home/claude/.claude/.credentials.json -o -e /home/claude/.claude.json' \
  && fail "credential or account state baked into the image" \
  || pass "no baked credentials in the config dir"
[ -z "$(run 'find /home/claude/.claude -type f 2>/dev/null')" ] \
  && pass "config dir holds no files in the image" || fail "config dir has files: $(run 'find /home/claude/.claude -type f')"

head_ "2. Identity and privilege"
[ "$(run 'id -u')" = 1000 ] && pass "default user is uid 1000, not root" || fail "default user is $(run 'id -u')"
[ -z "$(run 'find / -xdev -perm -4000 -type f 2>/dev/null')" ] \
  && pass "no setuid binaries" || fail "setuid binaries present: $(run 'find / -xdev -perm -4000 -type f 2>/dev/null' | tr '\n' ' ')"
run 'command -v sudo' >/dev/null && fail "sudo is installed" || pass "no sudo"
run 'command -v iptables' >/dev/null && fail "iptables is installed" || pass "no iptables"

head_ "3. Baked configuration"
run 'test -f /etc/claude-code/managed-settings.json' && pass "managed settings present" || fail "managed settings missing"
[ "$(run 'stat -c %a /etc/claude-code/managed-settings.json')" = 444 ] \
  && pass "managed settings are read-only" || fail "managed settings are writable"
run 'jq -e .hooks.PreToolUse /etc/claude-code/managed-settings.json' >/dev/null \
  && pass "PreToolUse guard is wired up" || fail "PreToolUse guard missing"
# These two keys must stay unset, or --yolo breaks and project settings stop applying.
run 'jq -e ".permissions.disableBypassPermissionsMode // empty" /etc/claude-code/managed-settings.json' >/dev/null \
  && fail "disableBypassPermissionsMode is set; --yolo will not work" \
  || pass "bypass mode not disabled in the base policy"
run 'jq -e ".allowManagedPermissionRulesOnly // empty" /etc/claude-code/managed-settings.json' >/dev/null \
  && fail "allowManagedPermissionRulesOnly is set; project settings will be ignored" \
  || pass "project permission rules still apply"
[ "$(run 'stat -c %a /usr/local/bin/sandbox-secret-guard')" = 555 ] \
  && pass "secret guard is not agent-writable" || fail "secret guard is writable"
# A Write(path) deny rule is NOT matched by file permission checks. The CLI
# warns at startup and the rule silently does nothing, so three rules here once
# protected nothing at all. Edit(path) covers every file-editing tool.
bad=$(run 'jq -r ".permissions.deny[]" /etc/claude-code/managed-settings.json | grep "^Write(" || true')
[ -z "$bad" ] && pass "no ineffective Write(path) deny rules" \
  || fail "Write(path) deny rules do nothing; use Edit(path): $(tr "\n" " " <<<"$bad")"
for f in '.git/hooks/**' '.github/workflows/**' '.devcontainer/**' '.mcp.json' '.claude/settings.json'; do
  run "jq -e '.permissions.deny | index(\"Edit($f)\")' /etc/claude-code/managed-settings.json" >/dev/null \
    && pass "Edit($f) is denied" || fail "Edit($f) is not denied"
done

head_ "4. The agent runs"
v=$(docker run --rm --entrypoint claude "$IMG" --version 2>/dev/null | head -1)
grep -q "$CLAUDE_CODE_VERSION" <<<"$v" && pass "agent reports $v" || fail "version mismatch: got '$v', want $CLAUDE_CODE_VERSION"

head_ "5. Secret guard blocks what it should"
guard() { docker run --rm -i --entrypoint /usr/local/bin/sandbox-secret-guard "$IMG" <<<"$1" >/dev/null 2>&1; echo $?; }
[ "$(guard '{"tool_name":"Write","tool_input":{"file_path":"/workspace/p/.git/hooks/pre-commit"}}')" = 2 ] \
  && pass "blocks writes to git hooks (the deferred-escape path)" || fail "git hook write was allowed"
[ "$(guard '{"tool_name":"Bash","tool_input":{"command":"cat /home/claude/.ssh/id_rsa"}}')" = 2 ] \
  && pass "blocks reads of ssh keys" || fail "ssh key read was allowed"
[ "$(guard '{"tool_name":"Edit","tool_input":{"file_path":"/workspace/p/src/main.rs"}}')" = 0 ] \
  && pass "allows ordinary source edits" || fail "ordinary edit was blocked"
# The self-widening vectors. These must hold even under --yolo, where deny
# rules are bypassed entirely, which is why they live in the hook as well.
[ "$(guard '{"tool_name":"Write","tool_input":{"file_path":"/workspace/p/.mcp.json"}}')" = 2 ] \
  && pass "blocks writes to .mcp.json" || fail ".mcp.json write was allowed"
[ "$(guard '{"tool_name":"Edit","tool_input":{"file_path":".claude/settings.json"}}')" = 2 ] \
  && pass "blocks writes to project settings" || fail "project settings write was allowed"
[ "$(guard '{"tool_name":"Bash","tool_input":{"command":"echo x >> .git/hooks/pre-push"}}')" = 2 ] \
  && pass "blocks shell writes into git hooks" || fail "shell write into git hooks was allowed"
# Reading these is legitimate and must stay allowed, or ordinary work suffers.
[ "$(guard '{"tool_name":"Read","tool_input":{"file_path":".claude/settings.json"}}')" = 0 ] \
  && pass "still allows reading project settings" || fail "reading project settings was blocked"
[ "$(guard '{"tool_name":"Bash","tool_input":{"command":"cat .github/workflows/ci.yml"}}')" = 0 ] \
  && pass "still allows reading workflow files" || fail "reading a workflow file was blocked"
head_ "6. Launcher argument handling"
# Regression: --shell used to discard passthrough args, so it could not be
# scripted and every non-interactive use silently did nothing.
out=$(cd /tmp && "$ROOT/bin/claude-sandbox" --offline --shell -- -c 'echo SHELL_PASSTHRU_OK' 2>/dev/null | tr -d '\r')
grep -q SHELL_PASSTHRU_OK <<<"$out" && pass "--shell passes arguments through" || fail "--shell dropped its arguments"
head_ "7. Plugin export and import"
SBX="$ROOT/bin/claude-sandbox"
tmp=$(mktemp -d)
# An archive reaching outside plugins/ must be refused: extracting it into the
# auth volume would overwrite .credentials.json or plant a settings file.
mkdir -p "$tmp/evil/plugins"; echo x > "$tmp/evil/.credentials.json"; echo x > "$tmp/evil/plugins/f"
tar czf "$tmp/evil.tgz" -C "$tmp/evil" .credentials.json plugins 2>/dev/null
if (cd "$tmp" && "$SBX" plugins import evil.tgz) >/dev/null 2>&1; then
  fail "import accepted an archive that writes outside plugins/"
else
  pass "import refuses an archive that escapes plugins/"
fi
# Export must never include the credential or session history.
if docker volume inspect "$AUTH_VOLUME" >/dev/null 2>&1 \
   && docker run --rm -v "$AUTH_VOLUME:/v:ro" --entrypoint test "$IMG" -d /v/plugins; then
  (cd "$tmp" && "$SBX" plugins export p.tgz) >/dev/null 2>&1
  if [ -f "$tmp/p.tgz" ]; then
    stray=$(tar tzf "$tmp/p.tgz" | grep -vE '^plugins(/|$)' | head -3)
    [ -z "$stray" ] && pass "export contains only the plugins subtree" \
      || fail "export leaked paths outside plugins/: $(tr '\n' ' ' <<<"$stray")"
  else
    fail "export produced no archive"
  fi
else
  skip "no plugins in the auth volume to export"
fi
rm -rf "$tmp"
head_ "8. The launcher is standalone"
# It gets copied to machines that have no checkout, so it must not need one.
sa=$(mktemp -d); cp "$ROOT/bin/claude-sandbox" "$sa/"
[ ! -f "$sa/versions.env" ] && pass "test fixture has no versions.env" || fail "fixture is not clean"
if CLAUDE_SANDBOX_ROOT="$sa" "$sa/claude-sandbox" --help >/dev/null 2>&1; then
  pass "runs with no repo files beside it"
else
  fail "launcher requires repo files it should carry as defaults"
fi
out=$(CLAUDE_SANDBOX_ROOT="$sa" "$sa/claude-sandbox" doctor 2>&1 || true)
grep -q 'base image' <<<"$out" && pass "doctor is built in, not a separate script" \
  || fail "doctor did not run standalone"
grep -q "$CLAUDE_CODE_VERSION" <<<"$out" \
  && pass "built-in default version matches versions.env ($CLAUDE_CODE_VERSION)" \
  || fail "built-in default version has drifted from versions.env"
# REGISTRY must match too, or a standalone copy pulls from the wrong namespace.
sa_reg=$(CLAUDE_SANDBOX_ROOT="$sa" "$sa/claude-sandbox" config 2>/dev/null | sed -n 's/^REGISTRY=//p')
[ "$sa_reg" = "$REGISTRY" ] \
  && pass "built-in default REGISTRY matches versions.env (${REGISTRY:-empty})" \
  || fail "built-in REGISTRY '$sa_reg' has drifted from versions.env '$REGISTRY'"
rm -rf "$sa"
summary

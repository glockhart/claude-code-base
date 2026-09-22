# shellcheck shell=bash
# Shared assertion helpers. Sourced, not executed.
PASS=0; FAIL=0
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$*"; PASS=$((PASS+1)); return 0; }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$*"; FAIL=$((FAIL+1)); return 0; }
skip() { printf '  \033[33mSKIP\033[0m  %s\n' "$*"; }
head_() { printf '\n\033[1m%s\033[0m\n' "$*"; }
summary() {
  printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ] || exit 1
}
need_docker() {
  docker info >/dev/null 2>&1 || {
    echo "Docker daemon is not running. Start Docker Desktop (macOS) or dockerd (Debian) and retry." >&2
    exit 2
  }
}

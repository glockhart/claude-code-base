#!/usr/bin/env bash
# shellcheck disable=SC2015  # `cond && pass || fail` is deliberate; both return 0
# shellcheck source=/dev/null
# Host-side preflight: is everything this sandbox needs actually present?
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/lib.sh"; set -a; . "$ROOT/versions.env"; set +a

head_ "Host"
command -v docker >/dev/null && pass "docker: $(docker --version)" || fail "docker not on PATH"
docker info >/dev/null 2>&1 && pass "daemon reachable" || fail "daemon not running"
docker compose version >/dev/null 2>&1 && pass "compose: $(docker compose version --short)" || fail "docker compose plugin missing"
printf '  \033[2mINFO\033[0m  platform %s, uid %s, gid %s\n' "$(uname -s)" "$(id -u)" "$(id -g)"
if [ "$(uname -s)" = Darwin ] || { [ "$(id -u)" = 1000 ] && [ "$(id -g)" = 1000 ]; }; then
  printf '  \033[2mINFO\033[0m  identity profile A (never root)\n'
else
  printf '  \033[2mINFO\033[0m  identity profile B (brief root, then gosu down)\n'
fi

head_ "Images and infrastructure"
docker image inspect "$BASE_IMAGE_NAME:$CLAUDE_CODE_VERSION" >/dev/null 2>&1 \
  && pass "base image $BASE_IMAGE_NAME:$CLAUDE_CODE_VERSION built" \
  || fail "base image missing; run: make build"
if docker network inspect "$NET_ISOLATED" >/dev/null 2>&1; then
  [ "$(docker network inspect "$NET_ISOLATED" -f '{{.Internal}}')" = true ] \
    && pass "network $NET_ISOLATED exists and is internal" \
    || fail "network $NET_ISOLATED exists but is NOT internal"
else
  fail "network $NET_ISOLATED missing; run: make proxy-up"
fi
[ "$(docker inspect -f '{{.State.Health.Status}}' claude-egress-proxy 2>/dev/null)" = healthy ] \
  && pass "egress proxy healthy" || fail "egress proxy not healthy; run: make proxy-up"
docker volume inspect "$AUTH_VOLUME" >/dev/null 2>&1 \
  && pass "auth volume exists" || skip "auth volume absent; run: make login"

head_ "Debian-only exposure"
if [ "$(uname -s)" = Linux ]; then
  # An internal network blocks traffic leaving the subnet, but the bridge
  # gateway address is IN the subnet, so host services on 0.0.0.0 are reachable.
  if iptables -C INPUT -s 10.99.0.0/24 -j DROP 2>/dev/null; then
    pass "host firewall drops input from the sandbox subnet"
  else
    fail "host is reachable from the sandbox. Run: sudo iptables -I INPUT -s 10.99.0.0/24 -j DROP"
  fi
else
  skip "host-gateway exposure is a native-Linux concern only"
fi
summary

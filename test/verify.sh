#!/usr/bin/env bash
# shellcheck disable=SC2015  # `cond && pass || fail` is deliberate; both return 0
# shellcheck source=/dev/null
# The security assertions. Needs the proxy running: make proxy-up
set -uo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
. "$ROOT/test/lib.sh"; set -a; . "$ROOT/versions.env"; set +a
need_docker
IMG=$BASE_IMAGE_NAME:$CLAUDE_CODE_VERSION

docker network inspect "$NET_ISOLATED" >/dev/null 2>&1 || { echo "run: make proxy-up" >&2; exit 2; }

# Run a command inside a container attached exactly as the launcher would.
sbx() {
  docker run --rm --network "$NET_ISOLATED" --dns "$PROXY_IP" \
    --cap-drop ALL --security-opt no-new-privileges:true --user 1000:1000 \
    -e HTTPS_PROXY="http://$PROXY_IP:$PROXY_PORT" \
    -e HTTP_PROXY="http://$PROXY_IP:$PROXY_PORT" \
    -e SANDBOX_EXPECT_PROXY=0 \
    --entrypoint bash "$IMG" -c "$1" 2>/dev/null
}

head_ "1. The network is genuinely internal"
[ "$(docker network inspect "$NET_ISOLATED" -f '{{.Internal}}')" = true ] \
  && pass "network is marked internal" || fail "network is NOT internal"
# The one that matters: bypass the proxy entirely. This proves the absence of a
# route, not merely that squid said no. A tool that ignores HTTPS_PROXY (plenty
# do) still cannot phone home.
out=$(sbx "timeout 5 bash -c 'exec 3<>/dev/tcp/1.1.1.1/443' && echo REACHED || echo BLOCKED")
[ "$out" = BLOCKED ] && pass "no direct route out, proxy bypassed" || fail "DIRECT EGRESS REACHABLE"
out=$(sbx "ip route show default | wc -l")
[ "${out:-0}" = 0 ] && pass "no default route in the container" || fail "a default route exists"

head_ "2. DNS is sinkholed"
# An internal network does NOT remove DNS on its own: Docker's resolver forwards
# queries host-side. With a CONNECT proxy the agent never needs to resolve, so
# the resolver points at an address with nothing on port 53.
out=$(sbx "timeout 5 getent hosts example.com >/dev/null && echo RESOLVED || echo NORESOLVE")
[ "$out" = NORESOLVE ] && pass "arbitrary names do not resolve" || fail "DNS resolution works; exfiltration channel is open"

head_ "3. The allowlist allows and denies correctly"
code=$(sbx "curl -s -o /dev/null -w '%{http_code}' --max-time 15 https://api.anthropic.com/v1/models")
[ -n "$code" ] && [ "$code" != 000 ] && [ "$code" != 403 ] \
  && pass "allowlisted host reachable (HTTP $code)" || fail "allowlisted host unreachable (got '${code:-none}')"
# A denied CONNECT never opens a tunnel, so curl reports exit 56 and an
# http_code of 000; the proxy's 403 is on the CONNECT itself. Match that
# explicitly, which also distinguishes "denied by the allowlist" from "the
# network is simply broken" (exit 7 or 28, with no 403 anywhere).
out=$(sbx "curl -sS -o /dev/null --max-time 15 https://example.com 2>&1")
grep -q 'response 403' <<<"$out" && pass "off-allowlist host refused by the proxy (403 on CONNECT)" \
  || fail "off-allowlist host: expected a 403 on CONNECT, got: ${out:-no output}"
out=$(sbx "curl -sS -o /dev/null --max-time 15 https://github.com 2>&1")
grep -q 'response 403' <<<"$out" && pass "github.com denied by default" \
  || skip "github.com not denied (allowlist.optional.conf is enabled)"

head_ "4. Privilege posture at runtime"
[ "$(sbx 'id -u')" = 1000 ] && pass "runs as uid 1000" || fail "unexpected uid"
[ "$(sbx 'grep CapEff /proc/self/status | awk "{print \$2}"')" = 0000000000000000 ] \
  && pass "no effective capabilities" || fail "capabilities retained: $(sbx 'grep CapEff /proc/self/status')"
[ "$(sbx 'grep NoNewPrivs /proc/self/status | awk "{print \$2}"')" = 1 ] \
  && pass "no-new-privileges is set" || fail "no-new-privileges is not set"
sbx 'test -S /var/run/docker.sock' && fail "docker socket is mounted" || pass "no docker socket"

head_ "5. The preflight fails closed"
# Preflight exits 70 for either of two reasons, and on the default bridge the
# proxy is always unreachable, so checking only the exit status would pass even
# when the egress check never ran. Assert the specific reason, and skip where
# the branch cannot be exercised.
probe=$(docker run --rm --entrypoint bash "$IMG" -c \
  "timeout 3 bash -c 'exec 3<>/dev/tcp/1.1.1.1/443' && echo UP || echo DOWN" 2>/dev/null)
if [ "$probe" != UP ]; then
  skip "this host cannot reach 1.1.1.1:443, so the direct-egress branch is unreachable"
else
  err=$(docker run --rm --user 1000:1000 \
          --entrypoint /usr/local/bin/sandbox-preflight "$IMG" 2>&1); rc=$?
  if [ "$rc" -eq 70 ] && grep -q 'direct egress reachable' <<<"$err"; then
    pass "preflight refuses, naming direct egress as the reason"
  else
    fail "preflight did not refuse for the right reason (rc=$rc): ${err:-no output}"
  fi
fi

head_ "6. Editor integration prerequisites"
# Regression: a tmpfs is root-owned by default, so the agent could not write the
# lockfile the VS Code extension discovers it by, and IDE integration broke.
out=$(docker run --rm --network "$NET_ISOLATED" --dns "$PROXY_IP" \
  --cap-drop ALL --security-opt no-new-privileges:true --user 1000:1000 \
  -e SANDBOX_EXPECT_PROXY=0 \
  --tmpfs "/home/claude/.claude/ide:rw,nosuid,nodev,size=1m,mode=0700,uid=1000,gid=1000" \
  --entrypoint bash "$IMG" -c 'stat -c %U /home/claude/.claude/ide; \
    printf x > /home/claude/.claude/ide/t.lock && echo WRITABLE || echo READONLY' 2>/dev/null)
grep -q claude <<<"$out" && pass "lockfile dir is owned by the agent" || fail "lockfile dir not agent-owned: $out"
grep -q WRITABLE <<<"$out" && pass "agent can write its IDE lockfile" || fail "agent cannot write the lockfile; IDE integration will not work"

head_ "7. Allowlist changes can be applied"
# Editing an allowlist is only useful if it can be applied. `squid -k
# reconfigure` signals the running master through its pid file, so a
# `pid_filename none` in squid.conf breaks this path entirely.
if "$ROOT/bin/claude-sandbox" proxy reload >/dev/null 2>&1; then
  pass "proxy reload applies allowlist changes without a restart"
else
  fail "proxy reload failed; an allowlist edit cannot be applied live"
fi
# Inspecting the health status here would report the stale pre-reload result,
# because the healthcheck interval is 15s. Run it synchronously.
docker exec claude-egress-proxy /usr/local/bin/squid-health \
  && pass "proxy answers correctly after reload" || fail "proxy unhealthy after reload"

head_ "8. Audit trail"
log=$(docker logs claude-egress-proxy 2>/dev/null | tail -200)
grep -qE 'CONNECT example\.com.*TCP_DENIED' <<<"$log" \
  && pass "denied attempt is in the audit trail, named" || fail "denial not recorded in the proxy log"
grep -q 'CONNECT api.anthropic.com' <<<"$log" \
  && pass "allowed attempt is in the audit trail, named" || skip "no allowed traffic logged yet"
# The healthcheck ran every few seconds and logged an aborted transaction each
# time, burying the real signal. Scope this to 127.0.0.1, which is the
# healthcheck. One aborted line per AGENT ip is the preflight reachability
# probe, one per container start, which is expected and useful.
grep -qE '^127\.0\.0\.1 .*transaction-end-before-headers' <<<"$log" \
  && fail "healthcheck is logging every interval and burying the audit trail" \
  || pass "audit trail is free of recurring healthcheck noise"
summary

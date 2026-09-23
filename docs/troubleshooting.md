# Troubleshooting

**`preflight FATAL: direct egress reachable`**
The container reached the internet without the proxy, so it is not on an
internal-only network. Usually a second network got attached. Check
`docker network inspect claude-egress_isolated -f '{{.Internal}}'` is `true`.
This is a real finding, not a false alarm: do not work around it.

**`preflight FATAL: proxy unreachable`**
`make proxy-up`.

**Something hangs instead of failing**
Almost always a blocked host. `claude-sandbox proxy logs` and look for
`TCP_DENIED/403`. Add the host to `proxy/allowlist.local.conf`, then
`claude-sandbox proxy reload`.

**`npm install` or `pip install` fails with no route**
The tool is ignoring the proxy environment variables. That is the correct
fail-closed behaviour. Configure the tool explicitly, or add its registry to
`proxy/allowlist.optional.conf`.

**`apt-get` fails at run time**
By design. The agent is non-root with no sudo. Put the package in the project's
`.claude-sandbox/Dockerfile`, where builds have ordinary egress.

**Files on the host are owned by 1000 or by root, on Debian**
Identity profile B did not engage. Check `claude-sandbox doctor` reports profile
B, and that the five capabilities are being granted.

**`--yolo refused: network is not internal`**
Working as intended. Unattended running is only defensible with egress
restricted. Start the proxy, or use `--offline`.

**The VS Code extension hangs, or does not see the agent**
If the extension restarted, terminals opened earlier hold a stale port. Close
and reopen the terminal. If two sandboxes are running, confirm the `ide` tmpfs
is mounted, otherwise they share lockfiles.

**Sign-in does not persist**
`CLAUDE_CONFIG_DIR` must point at the mounted volume, otherwise the account
state file lands outside it and dies with the container.

**git refuses: dubious ownership**
`safe.directory` is set system-wide in the image. If you see this, the workspace
is mounted somewhere unexpected.

**`error:transaction-end-before-headers` in the proxy log**
Expected, one line per container start. It is `sandbox-preflight` opening a
socket to confirm the proxy is reachable, then closing it without sending a
request. Squid logs aborted transactions regardless of the access-log ACL,
because there is no request to evaluate. A line every few seconds from
`127.0.0.1` would be different: that would be the healthcheck misconfigured, and
`make verify` fails on it.

**`could not pull ghcr.io/...`**
The packages are public and pull anonymously, so the usual cause is that a
freshly published package has not been made public yet. Packages always start
private, even from a public repository. Flip each one once: package page →
Package settings → Danger Zone → Change visibility.

If you would rather not depend on the registry, move the images across by hand:

```bash
# where the images exist
docker save claude-code-base:2.1.278 claude-sandbox-proxy:1 | gzip > imgs.tgz
# on the target machine
gunzip -c imgs.tgz | docker load
```

**The script behaves differently on two machines**
Run `claude-sandbox config` on each and compare. It prints every resolved value
and which files it read. Configuration precedence is environment variables,
then `~/.config/claude-sandbox/config`, then `versions.env` if the script sits
in a checkout, then built-in defaults. A stale config file on one host is the
usual cause.

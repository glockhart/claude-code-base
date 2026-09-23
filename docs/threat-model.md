# Threat model

The failure mode of a sandbox is someone believing it does more than it does.
This page is deliberately unflattering.

## What holds up

- **Egress to attacker-controlled infrastructure.** There is no route out, and
  the allowlist is enforced outside the blast radius. It survives a container
  restart and covers IPv6, because there is no IPv6 route either.
- **DNS-tunnelled exfiltration.** Closed by sinkholing the resolver. Worth
  noting that Anthropic's reference firewall script leaves this open, since it
  explicitly permits port 53.
- **Theft of host credentials.** SSH keys, cloud credentials, forge tokens and
  registry credentials are not in the container, so they cannot be taken from it.
- **Damage beyond one project.** Only the current repository is mounted.
- **Escalation to host root.** No Docker socket, no capabilities, no sudo, no
  setuid binaries, non-root user, `no-new-privileges`.
- **Publication of your code.** No push credential, and no route to a forge by
  default.
- **Resource exhaustion.** PID, memory and CPU limits.
- **A persistent implant.** The container is removed on exit. Persistence is
  confined to named volumes you can list and delete.
- **A hostile repo relaxing the rules.** Managed settings outrank project
  settings and live outside both the workspace and the auth volume.

## What does not hold up

**Kernel escape.** A container is not a security boundary against a kernel
exploit. On macOS the Docker Desktop VM is a second boundary. On native Debian a
successful escape is host root unless the daemon is rootless or using
user-namespace remapping. This is the sharpest difference between the two
targets.

**The Debian host itself is reachable.** An internal network blocks traffic
leaving the subnet, but the bridge gateway address is *in* the subnet. Anything
the host binds on all interfaces, a development database or a daemon on a TCP
port, is reachable from the sandbox. Mitigate on the Debian box:

```bash
sudo iptables  -I INPUT -s 10.99.0.0/24 -j DROP
sudo ip6tables -I INPUT -s fd00:99::/64 -j DROP
```

`claude-sandbox doctor` asserts this on Linux.

**Exfiltration through an allowlisted host.** With CONNECT, the proxy sees
`host:443` and nothing else. Not the path, not the query, not the body. Every
allowlisted entry is therefore a two-way channel bounded only by what that
server accepts. The Anthropic API can never be removed and accepts arbitrary
text in a prompt. The allowlist stops attacker-controlled *destinations*; it
does not stop exfiltration as a category. Do not let anyone describe this as
"the agent cannot leak data".

The compensating control is the access log. `claude-sandbox proxy logs` shows
every host reached for. A run that touches one host four hundred times during a
small task is visible.

**Deferred execution of planted code.** The strongest residual risk, and the one
a container cannot fix. The agent writes to your repo; that code later runs on
your machine or in CI with real credentials. Vectors include git hooks, package
scripts and `postinstall`, Makefiles, editor tasks, devcontainer files, workflow
files, and a lockfile pointing at a new registry.

Partly mitigated: the `PreToolUse` guard and the deny rules cover git hooks,
workflow files and devcontainer files. As host-side belt and braces:

```bash
git config --global core.hooksPath ~/.git-hooks   # ignore repo-local hooks
```

**The shell path is best-effort.** A tool call names its file, so the hook and
the deny rules see it exactly. A shell command does not: `cd .github/workflows`
may precede a write, while `cat .github/workflows/ci.yml` is an everyday read.
Refusing every mention would make ordinary work painful, so only the paths that
are dangerous *and* rarely read from a shell are blocked on mention: git hooks,
`.mcp.json`, and project settings files. Workflow and devcontainer files are
protected against the editing tools but not against a determined shell command.

But the real control is reading the diff before running anything.

**Theft of the container's own token.** Any process inside can read it, and
using it needs only the Anthropic API, which is allowlisted. This is
unavoidable: the agent must authenticate, so the credential is inside by
construction. Anthropic says the same thing about their own dev container.

It is mitigated by *scope*, not prevented. The container login is a separate
credential from your Mac's Keychain session. If it is stolen you revoke that one
and stay signed in on your laptop.

**Build-time supply chain.** Image builds run on the normal bridge with
unrestricted egress. Mitigated by pinning the agent to an exact version and
committing lockfiles. Pinning the base image by digest is the remaining step.

**Anything you deliberately mount.** Every `--env-file` and every allowlist
addition is an intentional hole. Inject only credentials that are task-scoped
and independently revocable.

**Squid itself.** It is now an attack surface reachable from the agent. It runs
unprivileged, read-only and cap-dropped, but rebuild it when Debian ships a
Squid security update.

## Two consequences

**Deny rules do not survive `--dangerously-skip-permissions`.** That flag
bypasses the permission engine, and the deny list with it. Since unattended
running is the point of building this, the deny rules are defence in depth for
ordinary sessions only. Anything that must hold in both modes lives in the
`PreToolUse` hook, which fires from the tool execution path independently of the
permission engine.

**SSH agent forwarding is close to pointless here.** A CONNECT proxy speaks
HTTP, so git over SSH is unreachable unless you allowlist arbitrary TCP to a
host, which is worse than the problem. Use an HTTPS remote with a scoped token.
The flag exists, with the cost labelled.

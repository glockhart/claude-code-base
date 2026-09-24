# claude-code-base

A disposable, network-restricted container for running Claude Code against any
repository, with no secrets in it by default.

The realistic threat is not a malicious model. It is **prompt injection**
reaching the agent through a repo's README, a dependency's post-install script,
or the output of a command it just ran. Filesystem isolation alone does not stop
an injected instruction from posting your source somewhere. So this pairs a
hardened container with a default-deny egress proxy, which is the combination
Anthropic's own guidance says is needed before letting an agent run unattended.

## Quick start, on a machine with the repo

```bash
make build            # both images, native arch
make proxy-up         # shared egress proxy and the two networks
make install          # symlink bin/claude-sandbox into ~/.local/bin
make login            # one-time; run /login and paste the code back

cd ~/git/some-project && claude-sandbox
```

## On every other machine, just the script

`bin/claude-sandbox` is standalone. It carries its own defaults and manages the
proxy with plain docker, so it needs no checkout, no Makefile and no compose
file. Copy the one file and go:

```bash
scp bin/claude-sandbox other-host:~/.local/bin/
ssh other-host
claude-sandbox pull      # fetches both images, no registry login needed
claude-sandbox login     # one-time Anthropic sign-in
cd ~/some-project && claude-sandbox
```

The images are published to GitHub Container Registry by Actions on merge to
main, and `REGISTRY` already points there. The packages are public, so pulls
need no registry authentication at all. See
[docs/publishing.md](docs/publishing.md).

Configuration precedence, highest first: environment variables, then
`~/.config/claude-sandbox/config`, then `versions.env` if the script happens to
sit in a checkout, then its built-in defaults. `make smoke` fails if a built-in
default drifts from `versions.env`.

Then verify it actually does what it claims:

```bash
make smoke            # image-only checks
make proxy-up && make verify   # the security assertions
claude-sandbox doctor # is the host set up correctly
```

## How it works

The agent container attaches to exactly one network, marked `internal`, so
Docker installs no NAT and no default route. A Squid sidecar sits on that
network and on a normal bridge, and allowlists by CONNECT hostname with no TLS
interception. Enforcement is **outside** the container: the agent has no
capability to change any of it from inside, and the rules survive a restart.

Name resolution is sinkholed too. An internal network does not remove DNS on its
own, because Docker's resolver forwards queries host-side, which is a working
exfiltration channel. With a CONNECT proxy the agent never needs to resolve
anything itself, so the resolver points at an address with nothing on port 53.

```
 agent container ──────── isolated (internal: true, no route out)
   HTTPS_PROXY=10.99.0.2:3128         │
   cap-drop ALL, non-root, --rm       │
                                   squid ──── external (bridge) ──── internet
                                  allowlist by hostname
                                  access log = audit trail
```

## Everyday use

| Command | What it does |
|---|---|
| `claude-sandbox` | Run the agent against the current repo |
| `claude-sandbox --yolo` | Skip permission prompts. Refuses unless egress is restricted |
| `claude-sandbox --shell` | Drop to bash in the sandbox instead |
| `claude-sandbox --offline` | No network at all, plus a stricter policy. For code you do not trust |
| `claude-sandbox --env-file F` | Inject secrets for one run only |
| `claude-sandbox proxy logs` | Watch every host the agent reaches for |
| `claude-sandbox plugins install URL [plugin…]` | Install from a Git marketplace, opening egress to that one host for that one command |
| `claude-sandbox plugins export` | Bundle installed plugins for another machine |
| `claude-sandbox plugins import F` | Restore that bundle here |
| `claude-sandbox doctor` | Check this host is set up correctly |
| `claude-sandbox pull` | Fetch both images from the configured registry |
| `claude-sandbox config` | Print what this machine actually resolved |

## What is not in the container

No SSH keys, no cloud credentials, no forge token, no Docker socket, no
`~/.gitconfig`, and none of your host Claude configuration. Git identity arrives
as environment variables so commits are attributed correctly.

The agent can commit. It cannot push, because there is no credential and, by
default, no route to a forge. You review the diff and push yourself. That human
checkpoint is enforced by the absence of a credential rather than by a policy
line, which is why it is the most valuable control here and costs nothing.

## Plugins

They persist in the auth volume, so no image rebuild is needed. The official
marketplace works with the default allowlist. Volumes are per Docker host, so
set them up once per host or copy the plugins subtree across. See
[docs/plugins.md](docs/plugins.md).

## Per-project images

Add `.claude-sandbox/Dockerfile` to a project and the launcher builds and caches
it automatically, keyed by content hash. See `examples/`.

## VS Code

Supported locally and cross-host. If the editor is on your Mac and Docker is on
another machine, use Remote SSH to that machine **first**, then reopen in the
container there. Docker cannot bind-mount your Mac's filesystem into a container
on another host, so the repo has to live where the daemon is. See
[docs/vscode.md](docs/vscode.md).

## Read this before trusting it

[docs/threat-model.md](docs/threat-model.md) is honest about what this does not
protect against. The short version: a container is not a boundary against a
kernel exploit, every allowlisted host is still a two-way channel, and the
strongest residual risk is code the agent plants in your repo that runs later on
your machine. **A sandbox that makes you comfortable skipping code review has
made you less safe.**

One asymmetry worth knowing up front: on macOS the Docker Desktop VM is a second
boundary. On native Debian a successful container escape is host root unless the
daemon is rootless or user-namespace remapped.

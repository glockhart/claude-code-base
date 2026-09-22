# VS Code

## The constraint that decides everything

Docker cannot bind-mount your local filesystem into a container running on a
remote host. There is no configuration where the repo sits on your Mac and the
container runs on Debian against those files.

So the tempting shortcut, pointing the editor's Docker setting at
`ssh://debian` and carrying on as if it were local, does not work. It builds and
runs remotely, but the workspace mount has nothing behind it.

## Local

Copy `templates/devcontainer.json` to `<repo>/.devcontainer/devcontainer.json`
and use **Dev Containers: Reopen in Container**.

## Cross-host: editor on the Mac, Docker on Debian

Microsoft's documented combination for this case is Remote SSH plus Dev
Containers, used together, in that order:

1. Remote SSH to the Debian box.
2. Open a folder that lives on that box.
3. **Dev Containers: Reopen in Container**.

No Docker client is needed on the Mac. The practical consequence is that
repositories you work on this way get cloned on the Debian box. Given the
sandbox already says commit inside and push from outside, that fits.

Requirements: key-based SSH, Docker on the Debian host, and the Docker endpoint
host must be a resolvable name or an IP. SSH config aliases are not honoured.

## Why it has to be that order

The extension opens a WebSocket server on loopback on a random high port, and
writes a lockfile naming that port and a per-window auth token into the `ide`
folder inside the config directory. The agent finds the lockfile, reads the
token, and connects over loopback. Nothing crosses a machine boundary.

Discovery works whenever the extension and the agent share a filesystem and a
loopback interface, which is exactly what happens when both end up inside the
container on the Debian box. It cannot work with the editor on the Mac and the
agent on Debian, because the Mac would be reading a lockfile describing a port
on a different machine's loopback.

**This is why the lockfile folder gets its own tmpfs.** It sits inside the
config directory, which is the volume shared across every project. Two
containers running at once would write lockfiles into the same folder, and each
agent could find the other's, pointing at a port on its own loopback that is
closed or belongs to something else. The launcher and the template both mount
`/home/claude/.claude/ide` as tmpfs so it is per-container and vanishes on exit.

## Egress

The server downloads itself into the container on first attach, and the
marketplace serves the extension. Behind a default-deny proxy neither happens,
and it presents as a hang rather than an error. Uncomment the hosts in
`proxy/allowlist.vscode.conf`, then `claude-sandbox proxy reload`.

Reassuringly, the editor attaches through the Docker daemon rather than over the
network, so no inbound port is opened and the egress posture is otherwise
unchanged.

## Two costs

**Containers stop being disposable.** The launcher removes the container on
exit. A dev container is long-lived by design and accumulates state. Rebuild it
periodically, and prefer the terminal launcher for anything you distrust.

**The extension weakens the boundary.** Trail of Bits documents that the Dev
Containers extension can drive host-side editor commands from a container
context, which is a path to running code on your machine that the terminal
launcher does not have. Keep the launcher as the default.

## Known rough edge

When the extension restarts it takes a new port and writes a new lockfile, but
terminals opened earlier keep the old port in their environment, and the agent
hangs looking for a server that has moved. Close and reopen the terminal.

## A simpler alternative

If you only want to drive an agent from the Mac without minding where it runs,
cloud sessions sidestep all of this: no lockfile to share, and the session
survives closing the laptop. Different trade, though, since the code and the
credential leave your machines entirely.

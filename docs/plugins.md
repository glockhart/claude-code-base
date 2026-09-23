# Plugins

**Plugins persist in a volume. You do not rebuild the image to install one.**

They live in `$CLAUDE_CONFIG_DIR/plugins`, inside the shared
`claude-sandbox-auth` volume. Install one once and it survives `--rm`, survives
an image rebuild, and is available in every project on that machine.

## The official marketplace works with the default allowlist

Despite being labelled "Source: GitHub", the official marketplace is fetched
from a Google Cloud Storage mirror, not cloned from GitHub. Since
`storage.googleapis.com` is already allowlisted, it installs on first run and
its plugins install normally, non-interactively:

```bash
claude plugin marketplace list
claude plugin install <name>@claude-plugins-official
```

Verified end to end in the sandbox with `github.com` denied.

**GitHub is only needed for third-party marketplaces** added straight from a
repository, such as `claude plugin marketplace add owner/repo`. Those fail
against the default allowlist, and the proxy log shows
`CONNECT github.com:443 ... TCP_DENIED`. To allow them, uncomment the GitHub
lines in `proxy/allowlist.optional.conf` and run `claude-sandbox proxy reload`.

## Moving plugins to another machine

A named Docker volume belongs to one Docker daemon. The volume on your Mac and
the volume on the Debian box are different volumes, so plugins do not transfer
by themselves.

Note the unit is the **Docker host**, not the machine you sit at. Working on
the Debian box over Remote SSH from the Mac uses the Debian volume, so that is
one place to set up, not two.

Two ways to reproduce them, both fine:

**Re-run the installs.** The commands are non-interactive, so a short script
run once per machine is the simplest reproducible answer, and it is the option
that keeps the credential out of it.

```bash
claude-sandbox --shell -- -c 'claude plugin install agent-sdk-dev@claude-plugins-official'
```

**Or copy the volume.** This works cleanly, because every path recorded inside
is container-absolute (`/home/claude/.claude/plugins/...`) and therefore
identical on any host. Nothing records a host home directory.

```bash
# on the source machine
docker run --rm -v claude-sandbox-auth:/src -v "$PWD":/out alpine \
  tar czf /out/plugins.tgz -C /src plugins

# on the target machine, after copying plugins.tgz across
docker run --rm -v claude-sandbox-auth:/dst -v "$PWD":/in alpine \
  tar xzf /in/plugins.tgz -C /dst
```

Verified: exporting and restoring into a fresh volume reproduces the full tree.

Export **only** the `plugins` subtree, as above. Taking the whole volume would
carry `.credentials.json` and your session history with it. Copying a
credential between machines is worth deciding on deliberately rather than doing
as a side effect of moving plugins.

## Two things to know

**Plugins are shared across every project.** The auth volume is deliberately
shared so you sign in once, and plugins ride along. A plugin installed while
working on one repo is active in all of them. To scope one to a single project,
declare it in that project's own `.claude/settings.json` instead.

**A plugin is code that runs inside the agent,** with the same reach: your
mounted repo, the auth token, and whatever the allowlist permits. The sandbox
bounds the blast radius, it does not vet the plugin.

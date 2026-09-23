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

**Or move them with the launcher.** This works cleanly because every path
recorded inside is container-absolute (`/home/claude/.claude/plugins/...`) and
therefore identical on any host. Nothing records a host home directory.

```bash
# on the source machine
claude-sandbox plugins export                 # writes claude-plugins-<date>.tgz
claude-sandbox plugins list                   # see what you have

# copy the archive across, then on the target machine
claude-sandbox plugins import claude-plugins-20260101.tgz
```

These are launcher subcommands rather than Make targets on purpose. The
launcher is the one thing that gets symlinked onto every machine; the Makefile
is repo tooling for building the image.

Two safety properties, both covered by `make smoke`:

- **Export takes only the `plugins` subtree.** The volume also holds
  `.credentials.json` and your session history. Moving a credential between
  machines should be a decision, not a side effect of moving plugins.
- **Import refuses an archive that reaches outside `plugins/`.** Extracting an
  arbitrary tarball into the auth volume could otherwise overwrite the
  credential or plant a settings file.

Import also fixes ownership to the uid the agent runs as. A plain `tar` as root
leaves files the agent cannot read, which presents as plugins silently not
loading.

## There is no declarative install, and it is worth knowing why

It would be tidier to declare plugins in the baked managed settings and have a
fresh machine pick them up with no install step. That does not work, and the
settings keys that look like they should do it do not.

`extraKnownMarketplaces` and `enabledPlugins` are real keys, settable at user,
project and managed scope. But `extraKnownMarketplaces` only registers a
marketplace as a place to browse, and `enabledPlugins` only toggles a plugin
that is **already installed**. Neither installs anything.

Confirmed two ways. The settings reference states plainly that none of the
plugin keys install a plugin. And declaring both keys in the sandbox, at
project scope and then at managed scope via a `managed-settings.d` drop-in,
started the agent cleanly but left `plugin marketplace list` and `plugin list`
both empty.

So installation is per Docker host, by running the commands. They are
non-interactive, which is what makes a short per-host script the answer.

Two related claims that also did not survive checking, recorded so they are not
retried: there is no `CLAUDE_CODE_PLUGIN_SEED_DIR` build-time seeding mechanism
in this version, and the official marketplace auto-install does **not** need
`github.com`, because it comes from the storage mirror.

## Two things to know

**Plugins are shared across every project.** The auth volume is deliberately
shared so you sign in once, and plugins ride along. A plugin installed while
working on one repo is active in all of them. To scope one to a single project,
declare it in that project's own `.claude/settings.json` instead.

**A plugin is code that runs inside the agent,** with the same reach: your
mounted repo, the auth token, and whatever the allowlist permits. The sandbox
bounds the blast radius, it does not vet the plugin.

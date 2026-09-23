# Plugins

**Plugins persist in a volume. You do not rebuild the image to install one.**

They live in `$CLAUDE_CONFIG_DIR/plugins`, which is inside the shared
`claude-sandbox-auth` volume. Install one once and it survives `--rm`, survives
an image rebuild, and is available in every project.

Verified: a file written to the plugins directory is still there in a fresh
container, and visible from a different project.

## The catch: most marketplaces are on GitHub

`github.com` is **not** in the default allowlist, and the official marketplace
is a GitHub repository. So installing from it fails until you opt in.

Reachable from the sandbox today:

| Host | Used for |
|---|---|
| `registry.npmjs.org` | npm-source plugin packages and their dependencies |
| `downloads.claude.ai` | plugin executable downloads |
| `storage.googleapis.com` | install counts and metadata in the plugin list |
| `raw.githubusercontent.com` | raw file fetches |

Denied by default: `github.com`, `codeload.github.com`,
`objects.githubusercontent.com`.

## Enabling GitHub marketplaces

Uncomment these in `proxy/allowlist.optional.conf`:

```
.github.com
.githubusercontent.com
codeload.github.com
```

Then apply it without dropping connections:

```bash
claude-sandbox proxy reload
```

Consider turning it back off once the plugin is installed. The plugin itself
keeps working, because it is already on the volume. See the note on GitHub as
an exfiltration channel in [threat-model.md](threat-model.md): what actually
binds is the absence of a write credential in the container, not the absence of
the host.

## Two things to know

**Plugins are shared across every project.** The auth volume is deliberately
shared so you sign in once. Plugins ride along, so a plugin installed while
working on one repo is active in all of them. If you want a plugin scoped to
one project, use that project's own `.claude/settings.json` rather than
installing it globally.

**A plugin is code that runs inside the agent.** It runs with the same reach as
the agent: your mounted repo, the auth token, and whatever the allowlist
permits. The sandbox contains the blast radius, it does not vet the plugin.
Install plugins you would be willing to run on the host.

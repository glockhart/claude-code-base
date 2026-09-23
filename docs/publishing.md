# Publishing

Both images are published to GitHub Container Registry by Actions when a pull
request merges to `main`. Nothing publishes from a branch, and nothing
publishes from a developer machine.

```
ghcr.io/glockhart/claude-code-base:2.1.278
ghcr.io/glockhart/claude-sandbox-proxy:1
```

Each also carries a `sha-<short>` tag and `latest`. The packages are public, so
they pull anonymously.

## One manual step after the first publish

**Packages are private on first publish even from a public repository.**
Visibility is independent of the repo and always starts private, and nothing in
the workflow changes it. So after the very first successful run, flip each
package once by hand:

Package page → gear icon → Package settings → Danger Zone → Change visibility →
Public. GitHub asks you to type the package name to confirm, and warns that
**this cannot be undone**.

Do it for both `claude-code-base` and `claude-sandbox-proxy`. Until you do,
`claude-sandbox pull` on another machine fails, because it is not signing in.

## Pulling on another machine

Nothing. Public container packages allow anonymous access, so:

```bash
claude-sandbox pull
```

No token, no `docker login`, no credential on disk. This is the main practical
benefit of public packages over private ones, beyond the billing.

## What is public, and what is not

Worth being clear about, since the repository is public too.

The images contain **no credentials**. Verified rather than assumed: no
credential-shaped strings in either image's build history, no tokens in the
environment, an empty Claude config directory, and a baked `gitconfig` with no
name or email. Your Anthropic login lives in a Docker volume created at runtime
by `claude-sandbox login`, and never enters an image.

What is readable: the egress allowlists, the managed settings, the guard
scripts and the entrypoint. All of that is in the public repository anyway. The
design does not rely on any of it being secret. The controls that matter are the
absence of a route out, the absence of credentials in the container, and dropped
capabilities, and none of those weaken by being known. See
[threat-model.md](threat-model.md).

## What runs when

| Event | Workflow | Result |
|---|---|---|
| Pull request | `ci.yml` | Lint, build both images, run both suites. Publishes nothing, and has `contents: read` only so it cannot |
| Push to `main` | `publish.yml` | Same checks, then build both images for both architectures and publish |
| Manual | either | `workflow_dispatch` |

A merged pull request is a push to `main`, whether merged, squashed or rebased,
so merging is what triggers a publish.

## How the publish is built

Five jobs:

1. **meta** reads the tags out of `versions.env` once, so nothing downstream
   parses it again or hardcodes a version.
2. **test** builds for the runner's own architecture and runs both suites. The
   publish is gated on this.
3. **build** is four jobs: two images across two platforms, each on a native
   runner, each pushing by digest.
4. **merge** stitches the per-platform digests into one manifest list per image
   and applies the tags. Until this runs, the pushed digests are untagged.
There is deliberately **no prune job**. See the storage section below.

Native arm64 runners are used rather than emulation. The base image build runs
`npm install -g`, a version assertion and a full-filesystem `find`, all of which
execute target-architecture binaries and crawl under QEMU.

## Things that will bite

**`claude-sandbox pull` always contacts the registry.** It deliberately does
not go through `ensure_image`, which returns early when an image already exists
locally. That short-circuit made `pull` a no-op on exactly the machines that
wanted an update, printing "images ready" without checking anything.

**A proxy policy change needs a tag bump.** `PROXY_IMAGE_TAG` is `1` and has no
reason to change on its own, but a machine that already holds
`claude-sandbox-proxy:1` will keep using it. If `squid.conf` or an allowlist
changes, bump the tag in `versions.env` and in the launcher's built-in default,
or existing machines keep the old policy. `make smoke` enforces that the two
stay in step.

**Pull requests from forks now run untrusted code on a runner.** That is
inherent to a public repository and the posture is the standard one: `ci.yml`
uses `pull_request`, not `pull_request_target`, so a fork's job gets a
read-only token and no secrets, and it cannot publish. The blast radius is an
ephemeral runner. Note that the publish workflow is untouched by this, since it
triggers only on push to `main`.

**Never set the build context to the repository root.** Each build job uses
`context: base` or `context: proxy`, matching the Makefile. Docker reads
`.dockerignore` from the root of the build context, so a root-level ignore file
silently changes what a root-context build can see. The repo had exactly such a
file, excluding everything but `base/`, which would have broken the proxy build
while the base build carried on succeeding.

**Both images must publish.** `claude-sandbox pull` fetches both, and
`proxy_up` calls `ensure_image` on the proxy. Publishing only the agent image
leaves the sandbox unable to start, which is what the old `make release` would
have done.

**Storage and transfer are free.** Package usage is unmetered for public
packages, so the measured ~536 MB for a two-architecture publish costs nothing,
and neither does untagged accumulation. Actions minutes are free on public
repositories too, and arm64 runners get four vCPUs rather than the two they
get on private ones.

**Pruning is still not automated, on purpose.** The obvious tool,
`actions/delete-package-versions` with `delete-only-untagged-versions`, is
unsafe for multi-architecture images: in a manifest list only the index carries
the tag, and the per-architecture children it points at are untagged versions.
That action will delete the children of a live `:latest`, leaving an index
pointing at nothing and pulls failing with `MANIFEST_UNKNOWN`. Prune
deliberately from the package page, or with a manifest-aware tool, once the
storage question above is settled.

**Re-pushing the same version tag is expected.** Any merge republishes the
current version unless it was bumped. The commit SHA tag is what distinguishes
two builds of one version, which is the reason it exists.

**Private repositories consume Actions minutes.** Unlike public ones, every
minute counts against the account allowance and then bills per minute. Layer
caching is scoped per image and per platform so the four build jobs do not evict
each other from the 10 GB repository cache.

## Bumping the agent version

```bash
make bump-claude VERSION=2.2.0   # edits versions.env
```

Then update the matching built-in default in `bin/claude-sandbox`. `make smoke`
fails if the two drift, and `claude-sandbox config` prints what a machine
actually resolved, which is the quickest way to compare two hosts.

Merge to main and CI publishes the new version.

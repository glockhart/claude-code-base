# Publishing

Both images are published to GitHub Container Registry by Actions when a pull
request merges to `main`. Nothing publishes from a branch, and nothing
publishes from a developer machine.

```
ghcr.io/glockhart/claude-code-base:2.1.278
ghcr.io/glockhart/claude-sandbox-proxy:1
```

Each also carries a `sha-<short>` tag and `latest`.

## The images are private, and stay private

A package's visibility is **independent of the repository's**. Packages inherit
a linked repository's *access permissions* but not its visibility, and the
default on first publish is private regardless of the repo. Nothing in the
workflow touches visibility.

**Making a package public is irreversible.** There is no way back to private,
so treat the visibility control on the package page as one-way.

## Pulling on another machine

You need a **classic** personal access token with the `read:packages` scope.
**Fine-grained tokens do not work with ghcr.io.** That is a GitHub limitation,
not a choice here, and it is the one genuinely awkward part of this setup.

```bash
echo "$CR_PAT" | docker login ghcr.io -u glockhart --password-stdin
claude-sandbox pull
```

The credential lands in `~/.docker/config.json` on the host. Note it never
enters the sandbox: the launcher pulls on the host, and `~/.docker` is not
among the paths mounted into the container.

Your everyday `gh` token is not enough. It carries `gist`, `read:org` and
`repo`, none of which grant package access.

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
5. **prune** deletes untagged versions left by earlier pushes.

Native arm64 runners are used rather than emulation. The base image build runs
`npm install -g`, a version assertion and a full-filesystem `find`, all of which
execute target-architecture binaries and crawl under QEMU.

## Things that will bite

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

**Pruning may fail on a personal account.** A repository that publishes a
package is granted admin on it, so `GITHUB_TOKEN` should be able to delete
untagged versions, but user-owned packages are a known rough edge. The prune job
is `continue-on-error`, so a permissions wrinkle cannot fail an otherwise good
publish. If it returns 403, create a classic token with `delete:packages`, store
it as a repository secret, and pass it as the job's `token`.

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

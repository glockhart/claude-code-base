# syntax=docker/dockerfile:1.7
# Claude Code sandbox base image.
#
# Deliberately absent: sudo, iptables, ipset. Egress is enforced outside this
# container by the Squid sidecar, so nothing in here needs to touch the network
# stack, and every one of those tools would only help an attacker.
#
# The agent is non-root with no sudo, so it cannot run apt at all. apt works
# only at image-build time, where the build container is on the normal bridge
# with ordinary egress. That is why no proxy address is baked into the image.

ARG NODE_IMAGE=node:22-bookworm-slim
# The tag lives in the ARG default above, and in versions.env; hadolint cannot
# resolve an ARG, so it sees an untagged FROM.
# hadolint ignore=DL3006
FROM ${NODE_IMAGE}

ARG CLAUDE_CODE_VERSION
ARG DEBIAN_FRONTEND=noninteractive

# Links the published package to the repository, so it inherits the repo's
# access permissions and shows its source. Without it the package is orphaned
# and access has to be managed by hand.
LABEL org.opencontainers.image.source="https://github.com/glockhart/claude-code-base"
LABEL org.opencontainers.image.description="Hardened, network-restricted sandbox for running Claude Code"
LABEL org.opencontainers.image.licenses="MIT"

# --- tooling -----------------------------------------------------------------
# Only what the sandbox itself needs, or what is useful in ANY repository.
# Language toolchains belong in per-project images layered on top of this one.
# Deliberately unpinned: a pinned apt version holds the image at a known-old
# package the day Debian ships a security update. Rebuilding is how this image
# takes those, so pinning would work against the thing it looks like it helps.
# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates curl git git-lfs openssh-client \
        less jq ripgrep fd-find unzip xz-utils procps \
        gosu tini vim-tiny bash-completion iproute2; \
    rm -rf /var/lib/apt/lists/*

# --- the agent ---------------------------------------------------------------
# Pinned exactly. The version check forces any lazy post-install download to
# happen NOW, while the build still has network, and fails loudly if the
# registry handed us something other than what we asked for.
RUN set -eux; \
    test -n "${CLAUDE_CODE_VERSION}"; \
    npm install -g "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}"; \
    npm cache clean --force; \
    installed=$(claude --version); \
    case "$installed" in \
      *"${CLAUDE_CODE_VERSION}"*) ;; \
      *) echo "installed '$installed', expected ${CLAUDE_CODE_VERSION}" >&2; exit 1 ;; \
    esac

# --- identity ----------------------------------------------------------------
# The node image already ships a `node` user at 1000:1000. Rename it rather than
# creating a second 1000, which would make the uid ambiguous.
RUN set -eux; \
    groupmod -n claude node; \
    usermod -l claude -d /home/claude -m node; \
    mkdir -p /home/claude/.claude /home/claude/.cache /workspace; \
    chown -R claude:claude /home/claude /workspace; \
    # Debian's skeleton .bash_logout runs `[ -x /usr/bin/clear_console ] && ...`,
    # which fails in a container because that binary is not installed. A LOGIN
    # shell runs it on the way out, so with `set -e` in the script the failure
    # becomes the shell's exit status: `claude-sandbox --shell -- -c 'set -e;
    # exit 5'` reported 1. It clears a console we do not have; delete it.
    rm -f /home/claude/.bash_logout

# --- hardening ----------------------------------------------------------------
# Debian ships su, mount, passwd, chfn, gpasswd, ssh-keysign and friends setuid
# root. no-new-privileges already blocks escalation through them, but stripping
# the bits removes the class entirely and nothing here needs them: the agent is
# non-root, there is no sudo, and gosu is not setuid.
RUN set -eux; \
    find / -xdev -perm /6000 -type f -exec chmod ug-s {} + 2>/dev/null || true; \
    test -z "$(find / -xdev -perm -4000 -type f 2>/dev/null)"

# --- baked configuration -----------------------------------------------------
COPY rootfs/ /
# --offline applies this. Baked in rather than bind-mounted from the repo so a
# standalone launcher can still use it; the entrypoint copies it into the
# drop-in directory when SANDBOX_OFFLINE=1.
COPY profiles/untrusted.json /etc/claude-code/profiles/untrusted.json
RUN set -eux; \
    chmod 0444 /etc/claude-code/managed-settings.json; \
    chmod 0555 /usr/local/bin/sandbox-secret-guard /usr/local/bin/sandbox-preflight
COPY --chmod=0555 entrypoint.sh /usr/local/bin/entrypoint.sh

ENV CLAUDE_CONFIG_DIR=/home/claude/.claude \
    HOME=/home/claude \
    NODE_OPTIONS=--use-system-ca \
    npm_config_cache=/home/claude/.cache/npm \
    EDITOR=vi \
    SHELL=/bin/bash

WORKDIR /workspace
USER claude

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["claude"]

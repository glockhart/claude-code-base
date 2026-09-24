# Own the proxy image rather than trusting a third-party one: it is the single
# enforcement point for the whole sandbox, and it is reachable from the agent.
FROM debian:bookworm-slim

LABEL org.opencontainers.image.source="https://github.com/glockhart/claude-code-base"
LABEL org.opencontainers.image.description="Default-deny egress proxy for the Claude Code sandbox"
LABEL org.opencontainers.image.licenses="MIT"

# Unpinned on purpose: this image is the enforcement point, so it has to be
# rebuildable onto Debian's current squid the day a security update lands.
# hadolint ignore=DL3008
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends squid ca-certificates; \
    rm -rf /var/lib/apt/lists/* /var/spool/squid/*; \
    # Our own config replaces the packaged one wholesale.
    rm -f /etc/squid/squid.conf

# Bake the policy in. A standalone launcher has no repo to bind-mount from, so
# the proxy has to be self-contained and pullable. Mounting over any of these
# at run time still works as an override.
COPY squid.conf /etc/squid/squid.conf
COPY allowlist.conf allowlist.optional.conf allowlist.vscode.conf /etc/squid/
# Local additions: present but empty, so squid does not error on a missing
# ACL file, and a bind mount can replace it.
RUN : > /etc/squid/allowlist.local.conf && chown proxy /etc/squid/allowlist.local.conf

COPY --chmod=0555 healthcheck.sh /usr/local/bin/squid-health

# uid 13 is the Debian `proxy` user squid runs as. The launcher gives the
# scratch tmpfs mounts that ownership explicitly, because a tmpfs is root-owned
# by default and squid then cannot write its pid file.
EXPOSE 3128

# In the image, not in a compose file, so `docker run` gets it too.
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=12 \
  CMD /usr/local/bin/squid-health
# -N foreground, -d1 log to stderr, -f explicit config path.
CMD ["squid", "-N", "-d1", "-f", "/etc/squid/squid.conf"]

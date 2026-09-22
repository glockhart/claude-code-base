# Own the proxy image rather than trusting a third-party one: it is the single
# enforcement point for the whole sandbox, and it is reachable from the agent.
FROM debian:bookworm-slim

RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends squid ca-certificates; \
    rm -rf /var/lib/apt/lists/* /var/spool/squid/*; \
    # Squid's packaged config is replaced wholesale by our mounted one.
    rm -f /etc/squid/squid.conf

COPY --chmod=0555 healthcheck.sh /usr/local/bin/squid-health

EXPOSE 3128
# -N foreground, -d1 log to stderr, -f explicit config path.
CMD ["squid", "-N", "-d1", "-f", "/etc/squid/squid.conf"]

ARG BASE_IMAGE=claude-code-base:2.1.278
FROM ${BASE_IMAGE}

USER root
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends default-jdk maven; \
    rm -rf /var/lib/apt/lists/*

USER claude
ENV MAVEN_OPTS=-Dmaven.repo.local=/home/claude/.cache/m2

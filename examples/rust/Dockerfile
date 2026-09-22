# Lives at <your-repo>/.claude-sandbox/Dockerfile. The launcher hashes this
# directory's contents and rebuilds only when they change.
ARG BASE_IMAGE=claude-code-base:2.1.278
FROM ${BASE_IMAGE}

USER root
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends build-essential pkg-config libssl-dev; \
    rm -rf /var/lib/apt/lists/*

USER claude
# Keep tool caches on the per-project cache volume so rebuilds start warm.
ENV CARGO_HOME=/home/claude/.cache/cargo \
    RUSTUP_HOME=/home/claude/.cache/rustup
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | sh -s -- -y --no-modify-path --default-toolchain stable
ENV PATH=/home/claude/.cache/cargo/bin:$PATH

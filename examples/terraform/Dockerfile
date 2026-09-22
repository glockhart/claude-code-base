ARG BASE_IMAGE=claude-code-base:2.1.278
FROM ${BASE_IMAGE}

ARG TERRAFORM_VERSION=1.9.8
USER root
RUN set -eux; \
    arch=$(dpkg --print-architecture); \
    curl -fsSL -o /tmp/tf.zip \
      "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_${arch}.zip"; \
    unzip -d /usr/local/bin /tmp/tf.zip; \
    rm /tmp/tf.zip; \
    terraform version

USER claude
# Reminder: this image has no cloud credentials. Inject them per run with
# --env-file, and only ever short-lived, narrowly scoped ones.

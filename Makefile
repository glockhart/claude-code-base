SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help
include versions.env
export

IMAGE := $(BASE_IMAGE_NAME):$(CLAUDE_CODE_VERSION)

.PHONY: help build build-proxy doctor proxy-up proxy-down proxy-logs login logout install lint test verify smoke bump-claude prune-projects

help: ## Show available targets
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-16s\033[0m %s\n",$$1,$$2}'

build: build-proxy ## Build both images for this machine's native arch
	docker build \
	  --build-arg CLAUDE_CODE_VERSION=$(CLAUDE_CODE_VERSION) \
	  --build-arg NODE_IMAGE=$(NODE_IMAGE) \
	  -t $(IMAGE) -t $(BASE_IMAGE_NAME):latest base

build-proxy: ## Build the egress proxy image
	docker build -t $(PROXY_IMAGE_NAME):$(PROXY_IMAGE_TAG) proxy

proxy-up: build-proxy ## Start the shared egress proxy and both networks
	./bin/claude-sandbox proxy up

proxy-down: ## Stop the egress proxy
	./bin/claude-sandbox proxy down

proxy-logs: ## Follow the egress audit trail
	./bin/claude-sandbox proxy logs

login: ## One-time sign-in; the token persists in the auth volume
	./bin/claude-sandbox login

logout: ## Delete the auth volume
	./bin/claude-sandbox logout

install: ## Symlink bin/claude-sandbox into ~/.local/bin
	mkdir -p $$HOME/.local/bin
	ln -sf $(CURDIR)/bin/claude-sandbox $$HOME/.local/bin/claude-sandbox
	@echo "linked $$HOME/.local/bin/claude-sandbox -> $(CURDIR)/bin/claude-sandbox"

lint: ## shellcheck the scripts, hadolint the Dockerfiles
	@fail=0; \
	if command -v shellcheck >/dev/null; then \
	  shellcheck --severity=warning bin/claude-sandbox base/entrypoint.sh \
	    base/rootfs/usr/local/bin/* test/*.sh || fail=1; \
	else \
	  echo "shellcheck not installed"; [ -z "$${CI:-}" ] || fail=1; \
	fi; \
	if command -v hadolint >/dev/null; then \
	  hadolint base/Dockerfile proxy/Dockerfile || fail=1; \
	else \
	  echo "hadolint not installed"; [ -z "$${CI:-}" ] || fail=1; \
	fi; \
	exit $$fail

doctor: ## Check this host is set up correctly
	./bin/claude-sandbox doctor

smoke: ## Fast checks that need only the built image
	./test/smoke.sh

verify: ## Full verification checklist (needs the proxy running)
	./test/verify.sh

test: smoke verify ## Everything

bump-claude: ## Pin a new agent version: make bump-claude VERSION=2.2.0
	@test -n "$(VERSION)" || { echo "usage: make bump-claude VERSION=x.y.z"; exit 1; }
	sed -i.bak 's/^CLAUDE_CODE_VERSION=.*/CLAUDE_CODE_VERSION=$(VERSION)/' versions.env && rm -f versions.env.bak
	@echo "pinned $(VERSION); now run: make build"

prune-projects: ## Remove per-project images not built on the current base
	@docker images --format '{{.Repository}}:{{.Tag}}' \
	  | grep '^claude-sandbox/' \
	  | grep -v ':$(CLAUDE_CODE_VERSION)-' \
	  | xargs -r docker rmi || true

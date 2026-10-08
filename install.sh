#!/usr/bin/env bash
# install.sh - install or update the claude-sandbox launcher.
#
#   curl -fsSL https://github.com/glockhart/claude-code-base/releases/latest/download/install.sh | bash
#   wget -qO-  https://github.com/glockhart/claude-code-base/releases/latest/download/install.sh | bash
#
# Re-running it is how you update. It needs no sudo and no docker; it puts one
# file on disk and checks its sha256 before it does.
#
# Environment:
#   CLAUDE_SANDBOX_INSTALL_DIR  where to install (default ~/.local/bin)
#   CLAUDE_SANDBOX_VERSION      a release tag, or "latest" (default)
#   CLAUDE_SANDBOX_BASE_URL     fetch from here instead of GitHub (testing)
#   CLAUDE_SANDBOX_FORCE=1      replace a symlink left by `make install`
#
# Everything sits inside main(), called on the last line, so a download cut off
# halfway through defines a function and runs nothing.
set -euo pipefail

main() {
  local repo=glockhart/claude-code-base name=claude-sandbox
  local dir=${CLAUDE_SANDBOX_INSTALL_DIR:-$HOME/.local/bin}
  local version=${CLAUDE_SANDBOX_VERSION:-latest}
  local base=${CLAUDE_SANDBOX_BASE_URL:-}
  if [ -z "$base" ]; then
    if [ "$version" = latest ]; then
      base=https://github.com/$repo/releases/latest/download
    else
      base=https://github.com/$repo/releases/download/$version
    fi
  fi

  die()  { printf '\033[31minstall:\033[0m %s\n' "$*" >&2; exit 1; }
  info() { printf '\033[2m[install]\033[0m %s\n' "$*" >&2; }
  warn() { printf '\033[33m[install]\033[0m %s\n' "$*" >&2; }

  if command -v curl >/dev/null 2>&1; then
    fetch() { curl -fsSL --retry 3 -o "$2" "$1"; }
  elif command -v wget >/dev/null 2>&1; then
    fetch() { wget -q -O "$2" "$1"; }
  else
    die "need curl or wget"
  fi

  local sha
  if command -v sha256sum >/dev/null 2>&1; then sha=(sha256sum)
  elif command -v shasum >/dev/null 2>&1; then sha=(shasum -a 256)
  else die "need sha256sum or shasum to verify the download"
  fi

  local target=$dir/$name
  # `make install` symlinks into a checkout. Replacing that link with a release
  # copy silently detaches a development setup, so ask first.
  if [ -L "$target" ] && [ "${CLAUDE_SANDBOX_FORCE:-}" != 1 ]; then
    die "$target is a symlink to $(readlink "$target"), probably from \`make install\`.
  Update the checkout with git instead, or re-run with CLAUDE_SANDBOX_FORCE=1
  to replace the link with the released script."
  fi

  local tmp
  tmp=$(mktemp -d)
  # shellcheck disable=SC2064  # expand now; tmp is local and gone by EXIT
  trap "rm -rf '$tmp'" EXIT

  info "downloading $name ($version)"
  fetch "$base/$name" "$tmp/$name" || die "could not download $base/$name"
  fetch "$base/$name.sha256" "$tmp/$name.sha256" || die "could not download $base/$name.sha256"

  local want got
  want=$(awk '{print $1; exit}' "$tmp/$name.sha256")
  got=$("${sha[@]}" < "$tmp/$name" | awk '{print $1}')
  [[ $want =~ ^[0-9a-f]{64}$ ]] || die "malformed checksum file"
  [ "$want" = "$got" ] || die "checksum mismatch: expected $want, got $got. Nothing was installed."
  bash -n "$tmp/$name" || die "downloaded script does not parse. Nothing was installed."

  local old=none
  if [ -f "$target" ]; then
    old=$(bash "$target" version 2>/dev/null | sed -n 's/^release //p') || true
    old=${old:-unknown}
  fi

  mkdir -p "$dir"
  # Copy into the target directory first so the final mv is a same-filesystem
  # rename, which is atomic: a copy that is running right now stays intact.
  local stage=$dir/.$name.tmp.$$
  cp "$tmp/$name" "$stage"
  chmod 0755 "$stage"
  mv -f "$stage" "$target"

  local new
  new=$(bash "$target" version 2>/dev/null | sed -n 's/^release //p') || true
  if [ "$old" = none ]; then
    info "installed $target (${new:-unknown})"
  else
    info "updated $target ($old -> ${new:-unknown})"
  fi

  case ":$PATH:" in
    *":$dir:"*) ;;
    *) warn "$dir is not on your PATH. Add this to your shell profile:
    export PATH=\"$dir:\$PATH\"" ;;
  esac

  if [ "$old" = none ]; then
    info "next: claude-sandbox pull && claude-sandbox login && claude-sandbox doctor"
  else
    info "next: claude-sandbox pull   # fetch the images this release expects"
  fi
}

main "$@"

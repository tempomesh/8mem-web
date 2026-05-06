#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  fi
  printf '%s\n' "8mem install failed: bash is required. Install bash, then rerun." >&2
  exit 1
fi

set -euo pipefail

REPO_URL="${EIGHTMEM_REPO_URL:-https://github.com/tempomesh/8mem.git}"
SOURCE_DIR="${EIGHTMEM_SOURCE_DIR:-$HOME/.8mem/src/8mem}"

info() {
  printf '%s\n' "$*"
}

fail() {
  printf '8mem install failed: %s\n' "$*" >&2
  exit 1
}

has_command() {
  command -v "$1" >/dev/null 2>&1
}

require_supported_platform() {
  case "$(uname -s)" in
    Darwin|Linux)
      ;;
    *)
      fail "unsupported OS. Use macOS, Linux, or WSL2 for this installer."
      ;;
  esac
}

require_tools() {
  has_command git || fail "git is required. Install git, then rerun this installer."
  has_command bash || fail "bash is required. Install bash, then rerun this installer."
}

check_repo_access() {
  if git ls-remote "$REPO_URL" HEAD >/dev/null 2>&1; then
    return
  fi

  info ""
  info "I cannot access the private 8mem repo from this terminal."
  info ""
  info "Private beta testers need local GitHub authentication first:"
  info "  gh auth login"
  info "  gh auth setup-git"
  info ""
  info "Then rerun:"
  info "  curl -fsSL https://8mem.com/install.sh | bash"
  fail "repo access check failed for $REPO_URL"
}

sync_source() {
  mkdir -p "$(dirname "$SOURCE_DIR")"
  if [ -d "$SOURCE_DIR/.git" ]; then
    info "Updating 8mem source: $SOURCE_DIR"
    git -C "$SOURCE_DIR" pull --ff-only
    return
  fi

  if [ -e "$SOURCE_DIR" ]; then
    fail "$SOURCE_DIR exists but is not a git checkout. Move it or set EIGHTMEM_SOURCE_DIR."
  fi

  info "Cloning 8mem source: $SOURCE_DIR"
  git clone "$REPO_URL" "$SOURCE_DIR"
}

main() {
  info "Installing 8mem private beta"
  require_supported_platform
  require_tools
  check_repo_access
  sync_source
  cd "$SOURCE_DIR"
  bash ./install.sh
}

main "$@"

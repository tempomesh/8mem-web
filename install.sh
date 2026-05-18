#!/usr/bin/env bash

if [ -z "${BASH_VERSION:-}" ]; then
  if command -v bash >/dev/null 2>&1; then
    exec bash "$0" "$@"
  fi
  printf '%s\n' "8mem install failed: bash is required. Install bash, then rerun." >&2
  exit 1
fi

set -euo pipefail

APP_NAME="8mem"
WHEEL_URL="${EIGHTMEM_WHEEL_URL:-https://8mem.com/app/install/8mem-0.1.0-py3-none-any.whl}"
WHEEL_SHA256="${EIGHTMEM_WHEEL_SHA256:-c9082cff0fe9a84543ad3ba4ad0f3e1ee34c248d8b8d914107725046f336ad7a}"
RUNTIME_HOME="${EIGHTMEM_HOME:-$HOME/.8mem}"
VENV_DIR="${EIGHTMEM_VENV:-$HOME/.8mem/venv}"
BIN_DIR="${EIGHTMEM_BIN_DIR:-$HOME/.local/bin}"
RUN_SETUP="${EIGHTMEM_RUN_SETUP:-1}"
SETUP_MODE="skipped"
OPENCLAW_WIRED="0"
OPENCLAW_WIRE_FAILED="0"
TELEGRAM_CONFIGURED="0"

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

require_python() {
  has_command python3 || fail "python3 is required. Install Python 3.11+ and rerun this installer."
  python3 - <<'PY'
import sys
if sys.version_info < (3, 11):
    raise SystemExit("Python 3.11+ is required")
PY
}

require_tools() {
  has_command curl || fail "curl is required. Install curl, then rerun this installer."
}

check_optional_ollama() {
  if has_command ollama; then
    info "Ollama detected."
  else
    info "Ollama not detected. 8mem can install first, but local model replies need Ollama."
    info "Install later with:"
    info "  curl -fsSL https://ollama.com/install.sh | sh"
  fi
}

create_venv() {
  info "Creating local 8mem environment: $VENV_DIR"
  python3 -m venv "$VENV_DIR"
  "$VENV_DIR/bin/python" -m pip install --upgrade pip >/dev/null
}

download_wheel() {
  mkdir -p "$RUNTIME_HOME/tmp"
  WHEEL_PATH="$RUNTIME_HOME/tmp/$(basename "$WHEEL_URL")"
  info "Downloading 8mem package:"
  info "  $WHEEL_URL"
  curl -fsSL "$WHEEL_URL" -o "$WHEEL_PATH"
  python3 - "$WHEEL_PATH" "$WHEEL_SHA256" <<'PY'
import hashlib
import sys
from pathlib import Path

path = Path(sys.argv[1])
expected = sys.argv[2].lower()
actual = hashlib.sha256(path.read_bytes()).hexdigest()
if actual != expected:
    raise SystemExit(f"SHA256 mismatch for {path.name}: expected {expected}, got {actual}")
PY
}

install_8mem() {
  info "Installing 8mem from verified package."
  "$VENV_DIR/bin/python" -m pip install --upgrade "$WHEEL_PATH"
}

install_command_shim() {
  mkdir -p "$BIN_DIR"
  ln -sf "$VENV_DIR/bin/8mem" "$BIN_DIR/8mem"
}

path_contains_bin_dir() {
  case ":$PATH:" in
    *":$BIN_DIR:"*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

has_interactive_tty() {
  [ -r /dev/tty ] && [ -w /dev/tty ] && { : < /dev/tty; } 2>/dev/null
}

run_setup() {
  if [ "$RUN_SETUP" != "1" ]; then
    info "Skipping setup because EIGHTMEM_RUN_SETUP=$RUN_SETUP"
    SETUP_MODE="skipped"
    return
  fi

  info ""
  info "Running first-time setup."
  if has_interactive_tty; then
    SETUP_MODE="interactive"
    "$VENV_DIR/bin/8mem" setup --mode both --skip-llm-check --no-next-steps < /dev/tty
    if [ -f "$HOME/.openclaw/openclaw.json" ]; then
      info ""
      info "OpenClaw detected - wiring Viri automatically."
      if "$VENV_DIR/bin/8mem" setup --mode openclaw --non-interactive --skip-telegram --skip-llm-check --no-status --no-next-steps; then
        OPENCLAW_WIRED="1"
      else
        OPENCLAW_WIRE_FAILED="1"
        info "OpenClaw wiring was skipped because setup could not safely update the workspace."
        info "Run this after fixing the OpenClaw workspace issue:"
        info "  8mem setup --mode openclaw"
      fi
    else
      info ""
      info "OpenClaw not detected. 8mem will run as a standalone memory bot if Telegram was configured."
    fi
  else
    SETUP_MODE="non_interactive"
    info "No interactive terminal detected; running safe non-interactive setup."
    "$VENV_DIR/bin/8mem" setup --non-interactive --skip-telegram --skip-llm-check --no-next-steps
  fi
  if [ -f "$RUNTIME_HOME/.env" ] && grep -q '^TELEGRAM_BOT_TOKEN=' "$RUNTIME_HOME/.env"; then
    TELEGRAM_CONFIGURED="1"
  fi
}

run_doctor() {
  info ""
  info "Running 8mem doctor."
  "$VENV_DIR/bin/8mem" doctor || true
}

print_next_steps() {
  info ""
  info "8mem installed."
  info ""
  info "Command installed at:"
  info "  $VENV_DIR/bin/8mem"
  info ""
  info "If your shell can see $BIN_DIR, you can run:"
  info "  8mem doctor"
  info "  8mem start"
  info "  8mem status"
  info ""
  if ! path_contains_bin_dir; then
    info "Your current shell PATH does not include $BIN_DIR."
    info "For this terminal, run:"
    info "  export PATH=\"$BIN_DIR:\$PATH\""
    info ""
    info "Or use the direct commands below."
    info ""
  fi
  info "If not, run:"
  info "  $VENV_DIR/bin/8mem doctor"
  info "  $VENV_DIR/bin/8mem start"
  info "  $VENV_DIR/bin/8mem status"
  info ""
  info "Local API key lookup for /v1 APIs:"
  info "  grep '^EIGHTMEM_LOCAL_API_KEY=' $RUNTIME_HOME/.env"
  info ""
  info "Then open:"
  info "  http://127.0.0.1:8787"
  info ""
  info "If Ollama is not installed yet:"
  info "  curl -fsSL https://ollama.com/install.sh | sh"
  info "  ollama pull qwen2.5:14b"
  info ""
  if [ "$TELEGRAM_CONFIGURED" != "1" ]; then
    info "For Telegram, rerun setup when you have your BotFather token:"
    info "  8mem setup --mode telegram"
  fi
  if [ "$OPENCLAW_WIRED" = "1" ]; then
    info ""
    info "OpenClaw was wired automatically."
    info "Test in Viri:"
    info "  /passport"
    info "  /compare coffee"
    info "  remember I prefer bullet points"
    info ""
    info "To undo OpenClaw wiring:"
    info "  8mem uninstall --mode openclaw"
  elif [ "$OPENCLAW_WIRE_FAILED" = "1" ]; then
    info ""
    info "OpenClaw was detected, but Viri was not wired automatically."
    info "Fix the workspace warning above, then run:"
    info "  8mem setup --mode openclaw"
  elif [ "$SETUP_MODE" != "interactive" ] && [ -f "$HOME/.openclaw/openclaw.json" ]; then
    info ""
    info "OpenClaw detected. Wire Viri with:"
    info "  8mem setup --mode openclaw"
  else
    info ""
    if [ "$TELEGRAM_CONFIGURED" = "1" ]; then
      info "Your standalone memory bot is configured."
      info "After starting 8mem, test in Telegram:"
      info "  /passport"
      info "  /compare productivity"
      info "  remember I prefer short answers"
    else
      info "OpenClaw not detected. 8mem is installed as a local memory server."
    fi
  fi
}

main() {
  info "Installing 8mem public beta"
  require_supported_platform
  require_python
  require_tools
  check_optional_ollama
  create_venv
  download_wheel
  install_8mem
  install_command_shim
  run_setup
  run_doctor
  print_next_steps
}

main "$@"

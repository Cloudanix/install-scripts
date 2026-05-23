# shellcheck shell=bash
# Cloudanix installers — shared helpers sourced by each product
# installer (./cloudanix-guard, etc.).
#
# Provides:
#   - `cdx::info`, `cdx::warn`, `cdx::err`, `cdx::ok` — coloured stderr
#   - `cdx::die <msg>` — print + exit 1
#   - `cdx::require_cmd <name>` — abort if a command is missing
#   - `cdx::python_bin` — echoes the python binary to use (≥ 3.9)
#   - `cdx::detect_os` — sets CDX_OS / CDX_ARCH
#   - `cdx::is_interactive` — true iff stdin is a TTY
#   - `cdx::confirm <prompt>` — y/n with default Y; auto-yes in non-interactive
#   - `cdx::ensure_tmpdir` — creates CDX_TMPDIR; cleaned up via EXIT trap
#   - `cdx::resolve_token <var>` — fetch a required env var or die helpfully
#
# All output goes to stderr by design; only data goes to stdout.

# ─── strict mode ────────────────────────────────────────────────────

cdx::init_strict() {
  set -euo pipefail
  # If the user pipes us into bash, $0 is "bash" — that's fine.
  # If they save us to a file and run, $0 is the file.
  IFS=$'\n\t'
}

# ─── colours (auto-disabled when stderr isn't a TTY) ────────────────

if [ -t 2 ] && [ "${NO_COLOR:-}" = "" ]; then
  CDX_C_RESET=$'\033[0m'
  CDX_C_DIM=$'\033[2m'
  CDX_C_RED=$'\033[31m'
  CDX_C_GREEN=$'\033[32m'
  CDX_C_YELLOW=$'\033[33m'
  CDX_C_BLUE=$'\033[34m'
  CDX_C_BOLD=$'\033[1m'
else
  CDX_C_RESET=""
  CDX_C_DIM=""
  CDX_C_RED=""
  CDX_C_GREEN=""
  CDX_C_YELLOW=""
  CDX_C_BLUE=""
  CDX_C_BOLD=""
fi

cdx::info() { printf '%s▸%s %s\n' "${CDX_C_BLUE}" "${CDX_C_RESET}" "$*" >&2; }
cdx::warn() { printf '%s!%s %s\n' "${CDX_C_YELLOW}" "${CDX_C_RESET}" "$*" >&2; }
cdx::err()  { printf '%s✗%s %s\n' "${CDX_C_RED}" "${CDX_C_RESET}" "$*" >&2; }
cdx::ok()   { printf '%s✓%s %s\n' "${CDX_C_GREEN}" "${CDX_C_RESET}" "$*" >&2; }
cdx::step() { printf '\n%s── %s ──%s\n' "${CDX_C_BOLD}" "$*" "${CDX_C_RESET}" >&2; }

cdx::die() {
  cdx::err "$*"
  exit 1
}

# ─── command + version checks ───────────────────────────────────────

cdx::require_cmd() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    cdx::die "required command not found: ${name}. Please install it and retry."
  fi
}

# Echo a python executable >= 3.9 found on PATH, or die.
# Honours an explicit CLOUDANIX_PYTHON if set.
cdx::python_bin() {
  local override="${CLOUDANIX_PYTHON:-}"
  local candidates=()
  if [ -n "$override" ]; then
    candidates+=("$override")
  fi
  candidates+=(python3.13 python3.12 python3.11 python3.10 python3.9 python3 python)

  local py
  for py in "${candidates[@]}"; do
    if command -v "$py" >/dev/null 2>&1 && cdx::_python_meets_minimum "$py"; then
      printf '%s' "$py"
      return 0
    fi
  done
  cdx::die "no Python ≥ 3.9 found on PATH. Tried: ${candidates[*]}. Set CLOUDANIX_PYTHON=/path/to/python to override."
}

# Internal: returns 0 iff $1 is python ≥ 3.9.
cdx::_python_meets_minimum() {
  "$1" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' \
    >/dev/null 2>&1
}

# ─── OS detection ───────────────────────────────────────────────────

# Sets CDX_OS = linux|darwin|windows  (we currently only ship for darwin/linux)
# Sets CDX_ARCH = amd64|arm64|...
cdx::detect_os() {
  local uname_s uname_m
  uname_s="$(uname -s 2>/dev/null || echo unknown)"
  uname_m="$(uname -m 2>/dev/null || echo unknown)"
  case "$uname_s" in
    Linux*)   CDX_OS=linux ;;
    Darwin*)  CDX_OS=darwin ;;
    MINGW*|MSYS*|CYGWIN*) CDX_OS=windows ;;
    *)        CDX_OS=unknown ;;
  esac
  case "$uname_m" in
    x86_64|amd64) CDX_ARCH=amd64 ;;
    arm64|aarch64) CDX_ARCH=arm64 ;;
    *) CDX_ARCH="$uname_m" ;;
  esac
  export CDX_OS CDX_ARCH
}

# ─── interactivity + prompting ─────────────────────────────────────

# True iff we have a TTY on stdin — i.e. the user can answer prompts.
# When piped through `curl ... | bash`, stdin is the pipe, so this is FALSE.
cdx::is_interactive() {
  [ -t 0 ]
}

# Y/n prompt with default Y.
# In non-interactive contexts, auto-answers yes UNLESS CLOUDANIX_ASSUME_NO=1.
cdx::confirm() {
  local prompt="$1"
  if ! cdx::is_interactive; then
    if [ "${CLOUDANIX_ASSUME_NO:-}" = "1" ]; then
      return 1
    fi
    return 0
  fi
  local reply
  printf '%s [Y/n] ' "$prompt" >&2
  read -r reply || return 1
  case "$reply" in
    n|N|no|NO|No) return 1 ;;
    *) return 0 ;;
  esac
}

# ─── temp dir lifecycle ────────────────────────────────────────────
#
# Use `cdx::ensure_tmpdir` (NOT a `$()`-based getter) to avoid this
# subtle subshell-trap bug: a function that does
#
#   mkdir; trap "rm -rf $dir" EXIT
#
# and is then called via `tmp="$(getter)"` registers the trap inside
# the command-substitution subshell. The subshell exits as soon as
# the assignment completes, so the trap fires *immediately* and the
# tmpdir is gone before the caller ever uses it. Setting CDX_TMPDIR
# from the parent shell (via the function body, no subshell) keeps
# the trap in the right scope.

CDX_TMPDIR=""

cdx::ensure_tmpdir() {
  if [ -z "$CDX_TMPDIR" ]; then
    CDX_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/cloudanix-install.XXXXXX")"
    # shellcheck disable=SC2064  # we want the trap to expand CDX_TMPDIR NOW
    trap "rm -rf -- '$CDX_TMPDIR'" EXIT INT TERM
  fi
}

# ─── required env var helper ───────────────────────────────────────

# Read a required env var; if missing/empty, print a helpful error and die.
# Usage: token=$(cdx::resolve_token CLOUDANIX_INSTALL_TOKEN "Get one at https://console.cloudanix.com/install-token")
cdx::resolve_token() {
  local varname="$1"
  local where="${2:-}"
  local value="${!varname:-}"
  if [ -z "$value" ]; then
    cdx::err "missing required env var: ${varname}"
    [ -n "$where" ] && cdx::err "  ${where}"
    cdx::err "  Example:"
    cdx::err "    ${varname}=\"<your-token>\" curl -fsSL https://install.cloudanix.com/<product> | bash"
    exit 1
  fi
  printf '%s' "$value"
}

# ─── pip helpers ───────────────────────────────────────────────────

# Run pip in quiet mode but surface errors. Always uses `python -m pip`
# so we hit the python we picked, not whichever pip is first on PATH
# (which may belong to a different python).
cdx::pip() {
  local py="$1"; shift
  "$py" -m pip --disable-pip-version-check "$@"
}

# Ensure pip exists on the chosen python; bootstrap via ensurepip if not.
cdx::ensure_pip() {
  local py="$1"
  if ! "$py" -m pip --version >/dev/null 2>&1; then
    cdx::info "pip not found on ${py}; bootstrapping via ensurepip…"
    "$py" -m ensurepip --upgrade >/dev/null 2>&1 \
      || cdx::die "could not bootstrap pip on ${py}. Install pip manually and retry."
  fi
}

# ─── banner ────────────────────────────────────────────────────────

cdx::banner() {
  local product="$1"
  local version="${2:-latest}"
  printf '\n' >&2
  printf '%s┌───────────────────────────────────────────────┐%s\n' "${CDX_C_DIM}" "${CDX_C_RESET}" >&2
  printf '%s│%s  Cloudanix installer · %-22s %s│%s\n' \
    "${CDX_C_DIM}" "${CDX_C_RESET}" "${product}" "${CDX_C_DIM}" "${CDX_C_RESET}" >&2
  printf '%s│%s  version: %-35s %s│%s\n' \
    "${CDX_C_DIM}" "${CDX_C_RESET}" "${version}" "${CDX_C_DIM}" "${CDX_C_RESET}" >&2
  printf '%s└───────────────────────────────────────────────┘%s\n' "${CDX_C_DIM}" "${CDX_C_RESET}" >&2
}

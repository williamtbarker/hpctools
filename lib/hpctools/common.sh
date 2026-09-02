#!/usr/bin/env bash

# Shared helpers for hpctools. Compatible with Bash 3.2 and newer.

# shellcheck disable=SC2034
HPCTOOLS_VERSION="0.1.0"

hpctools_error() {
  printf 'hpctools: error: %s\n' "$*" >&2
}

hpctools_die() {
  hpctools_error "$1"
  exit "${2:-1}"
}

hpctools_has_command() {
  command -v "$1" >/dev/null 2>&1
}

hpctools_require_command() {
  hpctools_has_command "$1" || hpctools_die "required command not found: $1" 127
}

hpctools_is_uint() {
  case "${1:-}" in
    ''|*[!0-9]*) return 1 ;;
    *) return 0 ;;
  esac
}

hpctools_is_positive_int() {
  hpctools_is_uint "${1:-}" && [ "$1" -gt 0 ]
}

hpctools_is_job_id() {
  case "${1:-}" in
    ''|*[!0-9_]*) return 1 ;;
  esac
  case "$1" in
    _*|*_|*__*) return 1 ;;
    *_*_* ) return 1 ;;
  esac
  return 0
}

hpctools_normalize_state() {
  printf '%s' "${1:-UNKNOWN}" \
    | tr '[:lower:]' '[:upper:]' \
    | sed 's/[+|].*$//; s/[[:space:]].*$//'
}

hpctools_is_terminal_state() {
  case "$(hpctools_normalize_state "${1:-}")" in
    COMPLETED|CANCELLED|FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|PREEMPTED|BOOT_FAIL|DEADLINE|REVOKED|SPECIAL_EXIT)
      return 0
      ;;
    *) return 1 ;;
  esac
}

hpctools_load_common() {
  return 0
}

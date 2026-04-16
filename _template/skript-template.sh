#!/usr/bin/env bash
# =============================================================================
# VCS Akadémia — Episode NN: <TITLE>
# -----------------------------------------------------------------------------
# YouTube:    VCS Akadémia
# GitHub:     https://github.com/VirtuCyberSecurity/vcs-akademia
# Source:     https://github.com/VirtuCyberSecurity/vcs-akademia/blob/main/NN-topic/<script-name>.sh
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/VirtuCyberSecurity/vcs-akademia/main/NN-topic/<script-name>.sh | bash
#
# Or download first, read it, then run:
#   curl -fsSL https://raw.githubusercontent.com/VirtuCyberSecurity/vcs-akademia/main/NN-topic/<script-name>.sh -o <script-name>.sh
#   less <script-name>.sh
#   bash <script-name>.sh
# =============================================================================

set -u
set -o pipefail

# -----------------------------------------------------------------------------
# Colors
# -----------------------------------------------------------------------------
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    C_RESET="$(tput sgr0)"
    C_RED="$(tput setaf 1)"
    C_GREEN="$(tput setaf 2)"
    C_YELLOW="$(tput setaf 3)"
    C_BLUE="$(tput setaf 4)"
    C_BOLD="$(tput bold)"
else
    C_RESET=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_BOLD=""
fi

# -----------------------------------------------------------------------------
# Output helpers
# -----------------------------------------------------------------------------
print_info()    { printf "%s[INFO]%s %s\n"    "${C_BLUE}"   "${C_RESET}" "$*"; }
print_success() { printf "%s[OK]%s %s\n"      "${C_GREEN}"  "${C_RESET}" "$*"; }
print_warning() { printf "%s[WARN]%s %s\n"    "${C_YELLOW}" "${C_RESET}" "$*" >&2; }
print_error()   { printf "%s[ERROR]%s %s\n"   "${C_RED}"    "${C_RESET}" "$*" >&2; }
print_header()  { printf "\n%s== %s ==%s\n\n" "${C_BOLD}"   "$*" "${C_RESET}"; }

# -----------------------------------------------------------------------------
# Root check — exits if not running as root
# -----------------------------------------------------------------------------
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        print_error "This script must be run as root (try: sudo bash $0)"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Confirmation prompt — exits on anything other than y/Y
# -----------------------------------------------------------------------------
confirm() {
    local prompt="${1:-Continue?}"
    local reply
    printf "%s%s [y/N]: %s" "${C_YELLOW}" "${prompt}" "${C_RESET}"
    read -r reply </dev/tty
    case "${reply}" in
        y|Y|yes|YES) return 0 ;;
        *) print_info "Cancelled by user."; exit 0 ;;
    esac
}

# -----------------------------------------------------------------------------
# Detect operating system (linux | macos | unknown)
# -----------------------------------------------------------------------------
detect_os() {
    case "$(uname -s)" in
        Linux*)  echo "linux" ;;
        Darwin*) echo "macos" ;;
        *)       echo "unknown" ;;
    esac
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
main() {
    print_header "VCS Akadémia — Episode NN: <TITLE>"
    print_info "Short description of what this script does."
    echo

    # --- Script logic goes here ---
    # Example:
    #   confirm "Proceed with installation?"
    #   print_info "Doing the thing..."
    #   if ! some_command; then
    #       print_error "Something went wrong."
    #       exit 1
    #   fi
    #   print_success "Done."

    print_header "Summary"
    print_success "All steps completed successfully."
}

# Trap to make sure we always print a clean failure message
on_exit() {
    local exit_code=$?
    if [ "${exit_code}" -ne 0 ]; then
        echo
        print_error "Script ended with errors (exit code ${exit_code})."
    fi
}
trap on_exit EXIT

main "$@"

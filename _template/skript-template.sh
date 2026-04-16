#!/usr/bin/env bash
# =============================================================================
# VCS Akadémia — Episode NN: <TITLE>
# -----------------------------------------------------------------------------
# YouTube:    youtube.com/@VCSAkademia
# GitHub:     github.com/VirtuCyberSecurity/vcs-akademia
#
# Usage (Mac/Linux terminal or Windows Git Bash):
#   curl -O https://raw.githubusercontent.com/VirtuCyberSecurity/vcs-akademia/main/NN-tema/<script-name>.sh
#   bash <script-name>.sh
#
# Windows users: install Git Bash from https://gitforwindows.org
# (ssh, ssh-keygen, ssh-copy-id and ~/.ssh all work the same as on Mac/Linux).
# =============================================================================

set -u
set -o pipefail

# -----------------------------------------------------------------------------
# Colors (ANSI escape codes)
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# -----------------------------------------------------------------------------
# Output helpers (Slovak-facing prefixes)
# -----------------------------------------------------------------------------
print_info()    { printf "${BLUE}[INFO]${NC} %s\n" "$*"; }
print_success() { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
print_warning() { printf "${YELLOW}[VAROVANIE]${NC} %s\n" "$*" >&2; }
print_error()   { printf "${RED}[CHYBA]${NC} %s\n" "$*" >&2; exit 1; }

# -----------------------------------------------------------------------------
# OS detection: linux | mac | windows | unknown
# -----------------------------------------------------------------------------
OS="unknown"
case "$(uname -s)" in
    Linux*)               OS="linux" ;;
    Darwin*)              OS="mac" ;;
    MSYS*|MINGW*|CYGWIN*) OS="windows" ;;
esac

if [ "$OS" = "unknown" ]; then
    print_error "Nepodporovaný operačný systém."
fi

# -----------------------------------------------------------------------------
# Confirmation prompt [y/N]
# -----------------------------------------------------------------------------
confirm() {
    local prompt="${1:-Pokračovať?}"
    local reply
    printf "${YELLOW}%s [y/N]:${NC} " "$prompt"
    read -r reply </dev/tty
    case "$reply" in
        y|Y|yes|YES|ano|ANO) return 0 ;;
        *) printf "${BLUE}[INFO]${NC} Zrušené.\n"; exit 0 ;;
    esac
}

# -----------------------------------------------------------------------------
# Platform-specific hooks — override in each episode as needed.
# Common logic (ssh, ssh-keygen, read, curl) stays OUTSIDE these functions.
# -----------------------------------------------------------------------------
install_dependencies() {
    case "$OS" in
        linux)   : ;;  # e.g. apt install ...
        mac)     : ;;  # e.g. brew install ...
        windows) : ;;  # e.g. hint to install via Git Bash / winget
    esac
}

restart_service() {
    case "$OS" in
        linux)   : ;;  # systemctl restart <name>
        mac)     : ;;  # launchctl kickstart -k system/<name>
        windows) : ;;  # net stop <name> && net start <name>
    esac
}

get_ssh_dir() {
    # ~/.ssh works on linux, mac and Windows Git Bash.
    echo "$HOME/.ssh"
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
main() {
    printf "\n${BLUE}== VCS Akadémia — Epizóda NN: <TITLE> ==${NC}\n\n"
    print_info "Stručný popis toho, čo skript urobí."
    echo

    confirm "Chceš pokračovať?"

    # --- Script logic goes here ---
    # Example:
    #   print_info "Robím prvú vec..."
    #   some_command || print_error "Prvý krok zlyhal."
    #   print_success "Prvý krok hotový."

    echo
    print_success "Hotovo — všetky kroky prebehli úspešne."
}

main "$@"

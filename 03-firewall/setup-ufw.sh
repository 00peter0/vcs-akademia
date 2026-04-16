#!/usr/bin/env bash
# =============================================================================
# VCS Akadémia — Episode 03: UFW Firewall
# -----------------------------------------------------------------------------
# YouTube:    youtube.com/@VCSAkademia
# GitHub:     github.com/VirtuCyberSecurity/vcs-akademia
#
# Usage (Mac/Linux terminal or Windows Git Bash):
#   curl -O https://raw.githubusercontent.com/VirtuCyberSecurity/vcs-akademia/main/03-firewall/setup-ufw.sh
#   bash setup-ufw.sh
#
# Windows users: install Git Bash from https://gitforwindows.org
# (ssh works the same as on Mac/Linux).
#
# This script runs LOCALLY on your computer. It:
#   1. Asks for VPS details, SSH port and extra ports to open.
#   2. Installs UFW on the VPS if missing.
#   3. Resets UFW, denies incoming, allows outgoing.
#   4. Allows the SSH port FIRST, then any extra ports.
#   5. Enables UFW and tests that SSH still works.
#   6. Shows the active firewall rules.
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
# Output helpers
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
# Ask for user input with optional default
# -----------------------------------------------------------------------------
ask() {
    local prompt="$1"
    local default="${2:-}"
    local reply
    if [ -n "$default" ]; then
        printf "%s [%s]: " "$prompt" "$default" >&2
    else
        printf "%s: " "$prompt" >&2
    fi
    read -r reply </dev/tty
    if [ -z "$reply" ]; then
        echo "$default"
    else
        echo "$reply"
    fi
}

# -----------------------------------------------------------------------------
# Check that required local tools exist
# -----------------------------------------------------------------------------
check_dependencies() {
    if ! command -v ssh >/dev/null 2>&1; then
        print_warning "Chýba nástroj: ssh"
        case "$OS" in
            windows) print_info "Na Windows potrebuješ Git Bash: https://gitforwindows.org" ;;
            mac)     print_info "Na Mac skús: brew install openssh" ;;
            linux)   print_info "Na Debian/Ubuntu: sudo apt install openssh-client" ;;
        esac
        print_error "Doinštaluj ssh a spusti skript znova."
    fi
}

# -----------------------------------------------------------------------------
# Validate a single TCP port (1–65535)
# -----------------------------------------------------------------------------
validate_port() {
    local p="$1"
    case "$p" in
        ''|*[!0-9]*) return 1 ;;
    esac
    if [ "$p" -lt 1 ] || [ "$p" -gt 65535 ]; then
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Validate a space-separated list of extra ports. Empty input is valid.
# -----------------------------------------------------------------------------
validate_extra_ports() {
    local list="$1"
    local p
    for p in $list; do
        if ! validate_port "$p"; then
            return 1
        fi
    done
    return 0
}

# -----------------------------------------------------------------------------
# Build the remote script that installs + configures UFW.
# Runs with root privileges on the VPS (see sudo_prefix below).
# -----------------------------------------------------------------------------
build_remote_script() {
    local ssh_port="$1" extra_ports="$2"

    local allow_extra=""
    local p
    for p in $extra_ports; do
        allow_extra="${allow_extra}ufw allow ${p}/tcp comment 'VCS Akademia' || exit 1"$'\n'
    done

    cat <<REMOTE_EOF
set -e

export DEBIAN_FRONTEND=noninteractive

if ! command -v ufw >/dev/null 2>&1; then
    echo "INSTALLING_UFW"
    apt-get update -qq
    apt-get install -y ufw
fi

ufw --force reset
ufw default deny incoming
ufw default allow outgoing

ufw allow ${ssh_port}/tcp comment 'SSH - VCS Akademia'

${allow_extra}
ufw --force enable

echo "UFW_CONFIGURED"
REMOTE_EOF
}

# -----------------------------------------------------------------------------
# Run the remote UFW configuration over SSH
# -----------------------------------------------------------------------------
configure_ufw_remote() {
    local ssh_user="$1" host="$2" conn_port="$3" ssh_port="$4" extra_ports="$5"

    local remote_script
    remote_script="$(build_remote_script "$ssh_port" "$extra_ports")"

    local sudo_prefix=""
    if [ "$ssh_user" != "root" ]; then
        sudo_prefix="sudo "
        print_warning "Pripájaš sa ako '$ssh_user' — na VPS sa použije sudo (možno si vyžiada heslo)."
    fi

    print_info "Konfigurujem UFW na VPS..."
    local output
    if ! output=$(ssh -p "$conn_port" \
             -o StrictHostKeyChecking=accept-new \
             "${ssh_user}@${host}" "${sudo_prefix}bash -s" <<<"$remote_script" 2>&1); then
        printf "%s\n" "$output" >&2
        print_error "Konfigurácia UFW zlyhala."
    fi

    if printf "%s" "$output" | grep -q "INSTALLING_UFW"; then
        print_success "UFW nainštalovaný."
    fi

    if ! printf "%s" "$output" | grep -q "UFW_CONFIGURED"; then
        printf "%s\n" "$output" >&2
        print_error "UFW sa nepodarilo nakonfigurovať."
    fi
    print_success "UFW pravidlá nastavené a firewall zapnutý."
}

# -----------------------------------------------------------------------------
# Test SSH connectivity after enabling UFW
# -----------------------------------------------------------------------------
test_ssh_after_ufw() {
    local ssh_user="$1" host="$2" port="$3"
    print_info "Testujem SSH spojenie po zapnutí UFW..."
    if ssh -p "$port" \
           -o BatchMode=yes \
           -o ConnectTimeout=10 \
           -o StrictHostKeyChecking=accept-new \
           "${ssh_user}@${host}" "echo ok" 2>/dev/null | grep -q "^ok$"; then
        return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# Show active UFW rules
# -----------------------------------------------------------------------------
show_ufw_status() {
    local ssh_user="$1" host="$2" port="$3"
    local sudo_prefix=""
    if [ "$ssh_user" != "root" ]; then
        sudo_prefix="sudo "
    fi

    print_info "Aktívne UFW pravidlá:"
    echo
    if ! ssh -p "$port" \
             -o StrictHostKeyChecking=accept-new \
             "${ssh_user}@${host}" "${sudo_prefix}ufw status verbose"; then
        print_warning "Nepodarilo sa získať výstup 'ufw status verbose'."
    fi
    echo
}

# -----------------------------------------------------------------------------
# Final summary box
# -----------------------------------------------------------------------------
print_summary_box() {
    local ssh_port="$1" extra_ports="$2"
    echo
    printf "${GREEN}╔════════════════════════════════════════════════╗${NC}\n"
    printf "${GREEN}║${NC}   ${BLUE}VCS Akadémia — Epizóda 03${NC}                    ${GREEN}║${NC}\n"
    printf "${GREEN}╠════════════════════════════════════════════════╣${NC}\n"
    printf "${GREEN}║${NC} ${GREEN}Firewall je aktívny${NC}                            ${GREEN}║${NC}\n"
    printf "${GREEN}║${NC} SSH port %-5s: povolený\n" "$ssh_port"
    local p
    for p in $extra_ports; do
        printf "${GREEN}║${NC} Port %-5s:     povolený\n" "$p"
    done
    printf "${GREEN}║${NC} Všetko ostatné: zakázané                       ${GREEN}║${NC}\n"
    printf "${GREEN}╚════════════════════════════════════════════════╝${NC}\n"
    echo
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
main() {
    printf "\n${BLUE}== VCS Akadémia — Epizóda 03: UFW Firewall ==${NC}\n\n"

    cat <<EOF
Tento skript nastaví UFW firewall na tvojom VPS:
  1. Zakáže všetky prichádzajúce spojenia.
  2. Povolí odchádzajúce spojenia.
  3. Povolí tvoj SSH port (PRED zapnutím UFW).
  4. Povolí ďalšie porty ktoré zadáš.
  5. Zapne UFW a otestuje že SSH stále funguje.
EOF
    echo

    print_warning "Tento skript mení firewall pravidlá na VPS."
    print_warning "Uisti sa že poznáš SSH port — inak sa zamkneš von."
    echo
    confirm "Chceš pokračovať?"

    printf "\n${BLUE}-- Kontrola závislostí --${NC}\n"
    check_dependencies
    print_success "ssh je dostupné."

    printf "\n${BLUE}-- Údaje o VPS --${NC}\n"
    local vps_host vps_port vps_user extra_ports
    vps_host="$(ask "IP adresa VPS" "")"
    if [ -z "$vps_host" ]; then
        print_error "IP adresa nesmie byť prázdna."
    fi

    vps_port="$(ask "SSH port" "22")"
    if ! validate_port "$vps_port"; then
        print_error "SSH port musí byť číslo v rozsahu 1–65535."
    fi

    vps_user="$(ask "Aktuálny user na VPS" "root")"
    if [ -z "$vps_user" ]; then
        print_error "Meno používateľa nesmie byť prázdne."
    fi

    echo
    print_info "Zadaj ďalšie porty oddelené medzerou (napr. 80 443 8080)."
    print_info "Stlač Enter ak nechceš otvoriť ďalšie porty."
    extra_ports="$(ask "Ďalšie porty" "")"
    if [ -n "$extra_ports" ] && ! validate_extra_ports "$extra_ports"; then
        print_error "Ďalšie porty musia byť čísla v rozsahu 1–65535, oddelené medzerami."
    fi

    echo
    printf "${BLUE}-- Zhrnutie --${NC}\n"
    print_info "Cieľ:          ${vps_user}@${vps_host}:${vps_port}"
    print_info "SSH port ${vps_port} — bude povolený"
    if [ -n "$extra_ports" ]; then
        local p
        for p in $extra_ports; do
            print_info "Port $p — bude povolený"
        done
    else
        print_info "Žiadne ďalšie porty."
    fi
    print_info "Všetky ostatné prichádzajúce spojenia — budú zakázané"
    echo
    confirm "Pokračovať s týmito nastaveniami?"

    printf "\n${BLUE}-- Krok 1/3 — Inštalácia a konfigurácia UFW --${NC}\n"
    configure_ufw_remote "$vps_user" "$vps_host" "$vps_port" "$vps_port" "$extra_ports"

    printf "\n${BLUE}-- Krok 2/3 — Test SSH po zapnutí UFW --${NC}\n"
    sleep 2
    if test_ssh_after_ufw "$vps_user" "$vps_host" "$vps_port"; then
        print_success "SSH funguje po zapnutí UFW."
    else
        echo
        print_warning "SSH nefunguje po zapnutí UFW!"
        print_warning "Pripoj sa cez emergency konzolu VPS providera."
        print_warning "Spusti: ufw allow ${vps_port}/tcp && ufw reload"
        print_warning "Prípadne úplne vypni firewall: ufw disable"
        exit 1
    fi

    printf "\n${BLUE}-- Krok 3/3 — Aktívne pravidlá --${NC}\n"
    show_ufw_status "$vps_user" "$vps_host" "$vps_port"

    print_summary_box "$vps_port" "$extra_ports"
    print_info "Prihlásenie: ssh -p $vps_port ${vps_user}@${vps_host}"
    print_info "Pre zmenu pravidiel na VPS: sudo ufw allow <port>/tcp && sudo ufw reload"
}

main "$@"

#!/usr/bin/env bash
# =============================================================================
# VCS Akadémia — Episode 04: Fail2ban — SSH ochrana
# -----------------------------------------------------------------------------
# YouTube:    youtube.com/@VCSAkademia
# GitHub:     github.com/VirtuCyberSecurity/vcs-akademia
#
# Usage (Mac/Linux terminal or Windows Git Bash):
#   curl -O https://raw.githubusercontent.com/00peter0/vcs-akademia/main/04-fail2ban/setup-fail2ban.sh
#   bash setup-fail2ban.sh
#
# Windows users: install Git Bash from https://gitforwindows.org
# (ssh works the same as on Mac/Linux).
#
# This script runs LOCALLY on your computer. It:
#   1. Asks for VPS details and Fail2ban thresholds.
#   2. Installs Fail2ban on the VPS if missing.
#   3. Writes /etc/fail2ban/jail.d/vcs-ssh.conf with the chosen thresholds.
#   4. Enables and (re)starts Fail2ban, then verifies the sshd jail.
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
# Validate integer in range
# -----------------------------------------------------------------------------
validate_int_range() {
    local n="$1" min="$2" max="$3"
    case "$n" in
        ''|*[!0-9]*) return 1 ;;
    esac
    if [ "$n" -lt "$min" ] || [ "$n" -gt "$max" ]; then
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Build the remote script that installs + configures Fail2ban.
# Runs with root privileges on the VPS (see sudo_prefix below).
# -----------------------------------------------------------------------------
build_remote_script() {
    local ssh_port="$1" maxretry="$2" findtime_s="$3" bantime_s="$4"

    cat <<REMOTE_EOF
set -e

export DEBIAN_FRONTEND=noninteractive

if ! command -v fail2ban-client >/dev/null 2>&1; then
    echo "INSTALLING_FAIL2BAN"
    apt-get update -qq
    apt-get install -y fail2ban
fi

mkdir -p /etc/fail2ban/jail.d

cat > /etc/fail2ban/jail.d/vcs-ssh.conf <<'CONF'
[sshd]
enabled = true
port = ${ssh_port}
filter = sshd
logpath = /var/log/auth.log
maxretry = ${maxretry}
findtime = ${findtime_s}
bantime = ${bantime_s}
backend = systemd
CONF

systemctl enable fail2ban >/dev/null 2>&1 || true
systemctl restart fail2ban

echo "FAIL2BAN_CONFIGURED"
REMOTE_EOF
}

# -----------------------------------------------------------------------------
# Run the remote Fail2ban configuration over SSH
# -----------------------------------------------------------------------------
configure_fail2ban_remote() {
    local ssh_user="$1" host="$2" conn_port="$3"
    local ssh_port="$4" maxretry="$5" findtime_s="$6" bantime_s="$7"

    local remote_script
    remote_script="$(build_remote_script "$ssh_port" "$maxretry" "$findtime_s" "$bantime_s")"

    local sudo_prefix=""
    if [ "$ssh_user" != "root" ]; then
        sudo_prefix="sudo "
        print_warning "Pripájaš sa ako '$ssh_user' — na VPS sa použije sudo (možno si vyžiada heslo)."
    fi

    print_info "Inštalujem a konfigurujem Fail2ban na VPS..."
    local output
    if ! output=$(ssh -p "$conn_port" \
             -o StrictHostKeyChecking=accept-new \
             "${ssh_user}@${host}" "${sudo_prefix}bash -s" <<<"$remote_script" 2>&1); then
        printf "%s\n" "$output" >&2
        print_error "Konfigurácia Fail2ban zlyhala."
    fi

    if printf "%s" "$output" | grep -q "INSTALLING_FAIL2BAN"; then
        print_success "Fail2ban nainštalovaný."
    else
        print_info "Fail2ban už bol nainštalovaný — preskakujem inštaláciu."
    fi

    if ! printf "%s" "$output" | grep -q "FAIL2BAN_CONFIGURED"; then
        printf "%s\n" "$output" >&2
        print_error "Fail2ban sa nepodarilo nakonfigurovať."
    fi
    print_success "Konfigurácia zapísaná do /etc/fail2ban/jail.d/vcs-ssh.conf."
    print_success "Fail2ban service zapnutý a reštartovaný."
}

# -----------------------------------------------------------------------------
# Verify Fail2ban is active on the VPS
# -----------------------------------------------------------------------------
verify_fail2ban_active() {
    local ssh_user="$1" host="$2" port="$3"
    local sudo_prefix=""
    if [ "$ssh_user" != "root" ]; then
        sudo_prefix="sudo "
    fi

    local state
    state="$(ssh -p "$port" \
            -o StrictHostKeyChecking=accept-new \
            "${ssh_user}@${host}" "${sudo_prefix}systemctl is-active fail2ban" 2>/dev/null || true)"

    if [ "$state" = "active" ]; then
        print_success "Fail2ban beží."
        return 0
    fi
    print_warning "Fail2ban nebeží, skontroluj manuálne: systemctl status fail2ban"
    return 1
}

# -----------------------------------------------------------------------------
# Show the sshd jail status
# -----------------------------------------------------------------------------
show_jail_status() {
    local ssh_user="$1" host="$2" port="$3"
    local sudo_prefix=""
    if [ "$ssh_user" != "root" ]; then
        sudo_prefix="sudo "
    fi

    print_info "Stav jail [sshd]:"
    echo
    if ! ssh -p "$port" \
             -o StrictHostKeyChecking=accept-new \
             "${ssh_user}@${host}" "${sudo_prefix}fail2ban-client status sshd"; then
        print_warning "Nepodarilo sa získať výstup 'fail2ban-client status sshd'."
    fi
    echo
}

# -----------------------------------------------------------------------------
# Final summary box
# -----------------------------------------------------------------------------
print_summary_box() {
    local ssh_port="$1" maxretry="$2" findtime_min="$3" bantime_min="$4"
    echo
    printf "${GREEN}╔════════════════════════════════════════════════╗${NC}\n"
    printf "${GREEN}║${NC}   ${BLUE}VCS Akadémia — Epizóda 04${NC}                    ${GREEN}║${NC}\n"
    printf "${GREEN}╠════════════════════════════════════════════════╣${NC}\n"
    printf "${GREEN}║${NC} ${GREEN}Fail2ban je aktívny${NC}                            ${GREEN}║${NC}\n"
    printf "${GREEN}║${NC} SSH port:         %-29s${GREEN}║${NC}\n" "$ssh_port"
    printf "${GREEN}║${NC} Ban po:           %-3s pokusoch%-17s${GREEN}║${NC}\n" "$maxretry" ""
    printf "${GREEN}║${NC} Sledované okno:   %-3s minút%-20s${GREEN}║${NC}\n" "$findtime_min" ""
    printf "${GREEN}║${NC} Dĺžka banu:       %-5s minút%-18s${GREEN}║${NC}\n" "$bantime_min" ""
    printf "${GREEN}║${NC}                                                ${GREEN}║${NC}\n"
    printf "${GREEN}║${NC} Aktívne bany:                                  ${GREEN}║${NC}\n"
    printf "${GREEN}║${NC}   fail2ban-client status sshd                  ${GREEN}║${NC}\n"
    printf "${GREEN}╚════════════════════════════════════════════════╝${NC}\n"
    echo
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
main() {
    printf "\n${BLUE}== VCS Akadémia — Epizóda 04: Fail2ban ==${NC}\n\n"

    cat <<EOF
Tento skript nainštaluje a nastaví Fail2ban na tvojom VPS:
  1. Sleduje neúspešné SSH prihlásenia.
  2. Po X pokusoch v okne Y minút zabanuje IP útočníka.
  3. Ban trvá Z minút, potom sa IP automaticky odbanuje.
  4. Beží na pozadí a štartuje pri reštarte servera.
EOF
    echo

    print_warning "Tento skript inštaluje balík a mení konfiguráciu na VPS."
    echo
    confirm "Chceš pokračovať?"

    printf "\n${BLUE}-- Kontrola závislostí --${NC}\n"
    check_dependencies
    print_success "ssh je dostupné."

    printf "\n${BLUE}-- Údaje o VPS --${NC}\n"
    local vps_host vps_port vps_user
    vps_host="$(ask "IP adresa VPS" "")"
    if [ -z "$vps_host" ]; then
        print_error "IP adresa nesmie byť prázdna."
    fi

    vps_port="$(ask "SSH port" "22")"
    if ! validate_int_range "$vps_port" 1 65535; then
        print_error "SSH port musí byť číslo v rozsahu 1–65535."
    fi

    vps_user="$(ask "User pre pripojenie" "root")"
    if [ -z "$vps_user" ]; then
        print_error "Meno používateľa nesmie byť prázdne."
    fi

    printf "\n${BLUE}-- Nastavenia Fail2ban --${NC}\n"
    local maxretry findtime_min bantime_min
    maxretry="$(ask "Počet neúspešných pokusov pred banom (1-20)" "5")"
    if ! validate_int_range "$maxretry" 1 20; then
        print_error "Počet pokusov musí byť číslo v rozsahu 1–20."
    fi

    findtime_min="$(ask "Čas sledovania pokusov v minútach (1-1440)" "10")"
    if ! validate_int_range "$findtime_min" 1 1440; then
        print_error "Čas sledovania musí byť číslo v rozsahu 1–1440 minút."
    fi

    bantime_min="$(ask "Dĺžka banu v minútach (1-10080 = 1 týždeň)" "60")"
    if ! validate_int_range "$bantime_min" 1 10080; then
        print_error "Dĺžka banu musí byť číslo v rozsahu 1–10080 minút."
    fi

    local findtime_s=$(( findtime_min * 60 ))
    local bantime_s=$(( bantime_min * 60 ))

    echo
    printf "${BLUE}-- Zhrnutie --${NC}\n"
    print_info "Cieľ:               ${vps_user}@${vps_host}:${vps_port}"
    print_info "Ban po:             ${maxretry} neúspešných pokusoch"
    print_info "Sledované okno:     ${findtime_min} minút"
    print_info "Dĺžka banu:         ${bantime_min} minút"
    echo
    confirm "Pokračovať?"

    printf "\n${BLUE}-- Krok 1/3 — Inštalácia a konfigurácia Fail2ban --${NC}\n"
    configure_fail2ban_remote "$vps_user" "$vps_host" "$vps_port" \
        "$vps_port" "$maxretry" "$findtime_s" "$bantime_s"

    printf "\n${BLUE}-- Krok 2/3 — Overenie že Fail2ban beží --${NC}\n"
    sleep 3
    verify_fail2ban_active "$vps_user" "$vps_host" "$vps_port" || true

    printf "\n${BLUE}-- Krok 3/3 — Stav SSH jail --${NC}\n"
    show_jail_status "$vps_user" "$vps_host" "$vps_port"

    print_summary_box "$vps_port" "$maxretry" "$findtime_min" "$bantime_min"
    print_info "Pre pozretie aktívnych banov kedykoľvek:"
    print_info "  ssh -p $vps_port ${vps_user}@${vps_host} \"sudo fail2ban-client status sshd\""
}

main "$@"

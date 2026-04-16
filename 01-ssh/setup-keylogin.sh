#!/usr/bin/env bash
# =============================================================================
# VCS Akadémia — Episode 01: SSH Key Login
# -----------------------------------------------------------------------------
# YouTube:    youtube.com/@VCSAkademia
# GitHub:     github.com/VirtuCyberSecurity/vcs-akademia
#
# Usage (Mac/Linux terminal or Windows Git Bash):
#   curl -O https://raw.githubusercontent.com/00peter0/vcs-akademia/main/01-ssh/setup-keylogin.sh
#   bash setup-keylogin.sh
#
# Windows users: install Git Bash from https://gitforwindows.org
# (ssh, ssh-keygen, ssh-copy-id and ~/.ssh all work the same as on Mac/Linux).
#
# This script runs LOCALLY on your computer. It:
#   1. Checks for an SSH key and generates one if missing (ed25519).
#   2. Copies your public key to the VPS via ssh-copy-id.
#   3. Disables password authentication on the VPS sshd_config.
#   4. Tests that key login works.
#   5. Prints the login command.
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
    local missing=""
    for cmd in ssh ssh-keygen ssh-copy-id; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing="$missing $cmd"
        fi
    done

    if [ -n "$missing" ]; then
        print_warning "Chýbajú nástroje:$missing"
        case "$OS" in
            windows)
                print_info "Na Windows potrebuješ Git Bash: https://gitforwindows.org"
                print_info "Ak Git Bash máš a ssh stále nie je k dispozícii, nainštaluj OpenSSH cez:"
                print_info "  Settings -> Apps -> Optional features -> Add feature -> OpenSSH Client"
                ;;
            mac)
                print_info "Na Mac sú ssh nástroje štandardne predinštalované."
                print_info "Ak chýbajú, skús: brew install openssh"
                ;;
            linux)
                print_info "Na Debian/Ubuntu: sudo apt install openssh-client"
                print_info "Na Fedora/RHEL:   sudo dnf install openssh-clients"
                ;;
        esac
        print_error "Doinštaluj chýbajúce nástroje a spusti skript znova."
    fi
}

# -----------------------------------------------------------------------------
# Ensure an ed25519 SSH key exists locally
# -----------------------------------------------------------------------------
ensure_keypair() {
    local key_path="$1"
    if [ -f "$key_path" ]; then
        print_info "SSH key už existuje, používam existujúci: $key_path"
        return 0
    fi

    print_info "Generujem SSH key..."
    mkdir -p "$(dirname "$key_path")"
    chmod 700 "$(dirname "$key_path")"
    if ! ssh-keygen -t ed25519 -f "$key_path" -N "" -C "vcs-akademia-$(date +%Y%m%d)" >/dev/null; then
        print_error "ssh-keygen zlyhal."
    fi
    print_success "Key vygenerovaný: $key_path"
}

# -----------------------------------------------------------------------------
# Copy public key to the VPS (this is the last time a password is entered)
# -----------------------------------------------------------------------------
copy_pubkey() {
    local key_path="$1" user="$2" host="$3" port="$4"

    print_info "Kopírujem key na VPS — zadaj heslo naposledy:"
    if ! ssh-copy-id -i "${key_path}.pub" -p "$port" "${user}@${host}"; then
        print_warning "ssh-copy-id zlyhal. Možné príčiny:"
        print_warning "  - nesprávna IP, username alebo port"
        print_warning "  - nesprávne heslo"
        print_warning "  - VPS je nedostupný (firewall, sieť)"
        print_warning "  - na VPS je vypnuté prihlasovanie heslom pre daného používateľa"
        print_error "Nepodarilo sa skopírovať verejný kľúč na VPS."
    fi
    print_success "Verejný kľúč je na VPS."
}

# -----------------------------------------------------------------------------
# Remote: backup sshd_config, disable password auth, restart sshd
# -----------------------------------------------------------------------------
harden_sshd() {
    local key_path="$1" user="$2" host="$3" port="$4"

    local remote_script
    remote_script=$(cat <<'REMOTE_EOF'
set -e

CONF="/etc/ssh/sshd_config"

if [ ! -f "$CONF" ]; then
    echo "sshd_config not found at $CONF" >&2
    exit 1
fi

cp "$CONF" "${CONF}.bak"
echo "Backup: ${CONF}.bak"

set_option() {
    key="$1"
    value="$2"
    if grep -qE "^[[:space:]]*#?[[:space:]]*${key}[[:space:]]+" "$CONF"; then
        sed -i -E "s|^[[:space:]]*#?[[:space:]]*${key}[[:space:]]+.*|${key} ${value}|" "$CONF"
    else
        printf "\n%s %s\n" "$key" "$value" >> "$CONF"
    fi
}

set_option PasswordAuthentication no
set_option PubkeyAuthentication  yes

if systemctl restart sshd 2>/dev/null; then
    echo "sshd restarted via systemctl (sshd)"
elif systemctl restart ssh 2>/dev/null; then
    echo "sshd restarted via systemctl (ssh)"
elif service ssh restart 2>/dev/null; then
    echo "sshd restarted via service ssh"
elif service sshd restart 2>/dev/null; then
    echo "sshd restarted via service sshd"
else
    echo "Could not restart sshd automatically." >&2
    exit 1
fi
REMOTE_EOF
)

    local sudo_prefix=""
    if [ "$user" != "root" ]; then
        sudo_prefix="sudo "
        print_warning "Používateľ '$user' nie je root — na VPS sa použije sudo (možno si vyžiada heslo)."
    fi

    print_info "Upravujem /etc/ssh/sshd_config na VPS..."
    if ! ssh -i "$key_path" -p "$port" -t \
             -o StrictHostKeyChecking=accept-new \
             "${user}@${host}" "${sudo_prefix}bash -s" <<<"$remote_script"; then
        print_warning "Vzdialený príkaz zlyhal — pripojenie funguje, ale konfigurácia sshd sa možno nezmenila."
        print_warning "Záloha (ak vznikla) je v /etc/ssh/sshd_config.bak — skontroluj VPS manuálne."
        return 1
    fi

    print_success "sshd_config upravený a sshd reštartovaný."
    return 0
}

# -----------------------------------------------------------------------------
# Test that key login works
# -----------------------------------------------------------------------------
test_key_login() {
    local key_path="$1" user="$2" host="$3" port="$4"
    print_info "Testujem key login..."
    if ssh -i "$key_path" -p "$port" \
           -o BatchMode=yes \
           -o ConnectTimeout=10 \
           -o StrictHostKeyChecking=accept-new \
           "${user}@${host}" "echo ok" 2>/dev/null | grep -q "^ok$"; then
        return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# Final summary box (only on full success)
# -----------------------------------------------------------------------------
print_summary_box() {
    local user="$1" host="$2" port="$3" key_path="$4"

    local title="VCS Akadémia — Epizóda 01"
    local lines=(
        "Hotovo!"
        "Prihlásenie: ssh -p ${port} ${user}@${host}"
        "Key: ${key_path}"
    )

    local max=${#title} line
    for line in "${lines[@]}"; do
        [ ${#line} -gt $max ] && max=${#line}
    done
    local width=$((max + 4))
    local border
    border=$(printf '═%.0s' $(seq 1 $width))

    echo
    printf "${GREEN}╔%s╗${NC}\n" "$border"
    printf "${GREEN}║${NC} ${BLUE}%s${NC}%*s${GREEN}║${NC}\n" "$title" $((width - ${#title} - 1)) ""
    printf "${GREEN}╠%s╣${NC}\n" "$border"
    for line in "${lines[@]}"; do
        printf "${GREEN}║${NC} %s%*s${GREEN}║${NC}\n" "$line" $((width - ${#line} - 1)) ""
    done
    printf "${GREEN}╚%s╝${NC}\n" "$border"
    echo
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
main() {
    printf "\n${BLUE}== VCS Akadémia — Epizóda 01: SSH Key Login ==${NC}\n\n"

    cat <<EOF
Tento skript urobí 5 krokov:
  1. Skontroluje / vygeneruje SSH key (~/.ssh/id_ed25519).
  2. Skopíruje verejný kľúč na VPS (heslo zadáš naposledy).
  3. Vypne prihlasovanie heslom na VPS.
  4. Otestuje, či key login funguje.
  5. Zobrazí príkaz na prihlásenie.

Po dokončení sa na VPS prihlásiš už iba so súkromným kľúčom.
EOF
    echo

    confirm "Chceš pokračovať?"

    printf "\n${BLUE}-- Kontrola závislostí --${NC}\n"
    check_dependencies
    print_success "ssh, ssh-keygen a ssh-copy-id sú dostupné."

    printf "\n${BLUE}-- Údaje o VPS --${NC}\n"
    local vps_host vps_user vps_port
    vps_host="$(ask "IP adresa VPS" "")"
    if [ -z "$vps_host" ]; then
        print_error "IP adresa nesmie byť prázdna."
    fi
    vps_user="$(ask "Username na VPS" "root")"
    vps_port="$(ask "SSH port" "22")"
    case "$vps_port" in
        ''|*[!0-9]*) print_error "Port musí byť číslo." ;;
    esac
    if [ "$vps_port" -lt 1 ] || [ "$vps_port" -gt 65535 ]; then
        print_error "Port musí byť v rozsahu 1–65535."
    fi

    local ssh_dir="$HOME/.ssh"
    local key_path="$ssh_dir/id_ed25519"

    echo
    print_info "Cieľ:     ${vps_user}@${vps_host}:${vps_port}"
    print_info "Key path: $key_path"
    echo
    confirm "Pokračovať s týmito údajmi?"

    printf "\n${BLUE}-- Krok 1/5 — SSH key --${NC}\n"
    ensure_keypair "$key_path"

    printf "\n${BLUE}-- Krok 2/5 — Kopírovanie verejného kľúča --${NC}\n"
    copy_pubkey "$key_path" "$vps_user" "$vps_host" "$vps_port"

    printf "\n${BLUE}-- Krok 3/5 — Vypnutie prihlasovania heslom --${NC}\n"
    print_warning "Na VPS sa upraví /etc/ssh/sshd_config a reštartuje sa sshd."
    confirm "Vypnúť prihlasovanie heslom na VPS?"
    local harden_ok=1
    if harden_sshd "$key_path" "$vps_user" "$vps_host" "$vps_port"; then
        harden_ok=0
    fi

    printf "\n${BLUE}-- Krok 4/5 — Test key loginu --${NC}\n"
    sleep 2
    if test_key_login "$key_path" "$vps_user" "$vps_host" "$vps_port"; then
        print_success "Key login funguje."
    else
        print_warning "Key login nefunguje. Skontroluj VPS manuálne."
        print_warning "Heslo zatiaľ môže fungovať — záloha je v /etc/ssh/sshd_config.bak"
        print_warning "Skript NEROBÍ automatický rollback — rozhodnutie je na tebe."
        print_info    "Debug:  ssh -v -i $key_path -p $vps_port ${vps_user}@${vps_host}"
        exit 1
    fi

    if [ "$harden_ok" -ne 0 ]; then
        print_warning "Key login síce funguje, ale sshd_config sa možno neupravil — skontroluj VPS."
    fi

    printf "\n${BLUE}-- Krok 5/5 — Hotovo --${NC}\n"
    print_summary_box "$vps_user" "$vps_host" "$vps_port" "$key_path"
    print_warning "Zálohuj si súkromný kľúč ($key_path) — ak ho stratíš, stratíš prístup."
}

main "$@"

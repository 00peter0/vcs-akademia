#!/usr/bin/env bash
# =============================================================================
# VCS Akadémia — Episode 02: Sudo User + Disable Root Login
# -----------------------------------------------------------------------------
# YouTube:    youtube.com/@VCSAkademia
# GitHub:     github.com/VirtuCyberSecurity/vcs-akademia
#
# Usage (Mac/Linux terminal or Windows Git Bash):
#   curl -O https://raw.githubusercontent.com/VirtuCyberSecurity/vcs-akademia/main/02-sudo-user/setup-sudo-user.sh
#   bash setup-sudo-user.sh
#
# Windows users: install Git Bash from https://gitforwindows.org
# (ssh, ssh-keygen and ~/.ssh all work the same as on Mac/Linux).
#
# This script runs LOCALLY on your computer. It:
#   1. Asks for VPS details and a new username.
#   2. Creates the user on the VPS and grants passwordless sudo.
#   3. Copies your SSH key to the new user.
#   4. Tests login as the new user.
#   5. Disables root login in sshd_config (only if the test passed).
#   6. Verifies that root login is really blocked.
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
    for cmd in ssh ssh-keygen; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing="$missing $cmd"
        fi
    done

    if [ -n "$missing" ]; then
        print_warning "Chýbajú nástroje:$missing"
        case "$OS" in
            windows)
                print_info "Na Windows potrebuješ Git Bash: https://gitforwindows.org"
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
# Validate Linux username: lowercase letters, digits, hyphen; min 3 chars;
# must start with a letter (standard useradd rules, simplified).
# -----------------------------------------------------------------------------
validate_username() {
    local name="$1"
    if [ ${#name} -lt 3 ]; then
        return 1
    fi
    case "$name" in
        [a-z]*) : ;;
        *) return 1 ;;
    esac
    case "$name" in
        *[!a-z0-9-]*) return 1 ;;
    esac
    return 0
}

# -----------------------------------------------------------------------------
# Create the sudo user on the VPS
# -----------------------------------------------------------------------------
create_remote_user() {
    local key_path="$1" ssh_user="$2" host="$3" port="$4" new_user="$5"

    local remote_script
    remote_script=$(cat <<REMOTE_EOF
set -e

NEW_USER="${new_user}"

if id "\$NEW_USER" >/dev/null 2>&1; then
    echo "USER_EXISTS"
else
    useradd -m -s /bin/bash "\$NEW_USER"
    echo "USER_CREATED"
fi

usermod -aG sudo "\$NEW_USER"

SUDOERS_FILE="/etc/sudoers.d/\$NEW_USER"
printf '%s ALL=(ALL) NOPASSWD:ALL\n' "\$NEW_USER" > "\$SUDOERS_FILE"
chmod 440 "\$SUDOERS_FILE"

echo "SUDO_CONFIGURED"
REMOTE_EOF
)

    local sudo_prefix=""
    if [ "$ssh_user" != "root" ]; then
        sudo_prefix="sudo "
        print_warning "Pripájaš sa ako '$ssh_user' — na VPS sa použije sudo (možno si vyžiada heslo)."
    fi

    print_info "Vytváram používateľa '$new_user' na VPS..."
    local output
    if ! output=$(ssh -i "$key_path" -p "$port" \
             -o StrictHostKeyChecking=accept-new \
             "${ssh_user}@${host}" "${sudo_prefix}bash -s" <<<"$remote_script" 2>&1); then
        printf "%s\n" "$output" >&2
        print_error "Nepodarilo sa vytvoriť používateľa na VPS."
    fi

    if printf "%s" "$output" | grep -q "USER_EXISTS"; then
        print_warning "Používateľ '$new_user' už existoval — pokračujem s ním."
    else
        print_success "Používateľ '$new_user' vytvorený."
    fi

    if ! printf "%s" "$output" | grep -q "SUDO_CONFIGURED"; then
        print_error "Sudo konfigurácia zlyhala."
    fi
    print_success "Passwordless sudo nastavené (/etc/sudoers.d/$new_user)."
}

# -----------------------------------------------------------------------------
# Copy authorized_keys from the current SSH user's home to the new user
# -----------------------------------------------------------------------------
copy_authorized_keys() {
    local key_path="$1" ssh_user="$2" host="$3" port="$4" new_user="$5"

    local remote_script
    remote_script=$(cat <<REMOTE_EOF
set -e

NEW_USER="${new_user}"
SRC_USER="${ssh_user}"

if [ "\$SRC_USER" = "root" ]; then
    SRC_KEYS="/root/.ssh/authorized_keys"
else
    SRC_KEYS="/home/\$SRC_USER/.ssh/authorized_keys"
fi

if [ ! -f "\$SRC_KEYS" ]; then
    echo "MISSING_SRC_KEYS \$SRC_KEYS" >&2
    exit 1
fi

DST_DIR="/home/\$NEW_USER/.ssh"
DST_KEYS="\$DST_DIR/authorized_keys"

mkdir -p "\$DST_DIR"
cp "\$SRC_KEYS" "\$DST_KEYS"
chown -R "\$NEW_USER:\$NEW_USER" "\$DST_DIR"
chmod 700 "\$DST_DIR"
chmod 600 "\$DST_KEYS"

echo "KEYS_COPIED"
REMOTE_EOF
)

    local sudo_prefix=""
    if [ "$ssh_user" != "root" ]; then
        sudo_prefix="sudo "
    fi

    print_info "Kopírujem authorized_keys na '$new_user'..."
    local output
    if ! output=$(ssh -i "$key_path" -p "$port" \
             -o StrictHostKeyChecking=accept-new \
             "${ssh_user}@${host}" "${sudo_prefix}bash -s" <<<"$remote_script" 2>&1); then
        printf "%s\n" "$output" >&2
        print_error "Nepodarilo sa skopírovať SSH key."
    fi

    if ! printf "%s" "$output" | grep -q "KEYS_COPIED"; then
        print_error "Kopírovanie authorized_keys zlyhalo."
    fi
    print_success "SSH key skopírovaný (/home/$new_user/.ssh/authorized_keys)."
}

# -----------------------------------------------------------------------------
# Test that the new user can log in with the key
# -----------------------------------------------------------------------------
test_new_user_login() {
    local key_path="$1" host="$2" port="$3" new_user="$4"
    print_info "Testujem prihlásenie cez '$new_user'..."
    if ssh -i "$key_path" -p "$port" \
           -o BatchMode=yes \
           -o ConnectTimeout=10 \
           -o StrictHostKeyChecking=accept-new \
           "${new_user}@${host}" "echo ok" 2>/dev/null | grep -q "^ok$"; then
        return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# Disable root login via the new sudo user
# -----------------------------------------------------------------------------
disable_root_login() {
    local key_path="$1" host="$2" port="$3" new_user="$4"

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

if grep -qE "^[[:space:]]*#?[[:space:]]*PermitRootLogin[[:space:]]+" "$CONF"; then
    sed -i -E "s|^[[:space:]]*#?[[:space:]]*PermitRootLogin[[:space:]]+.*|PermitRootLogin no|" "$CONF"
else
    printf "\nPermitRootLogin no\n" >> "$CONF"
fi

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

    print_info "Zakazujem root login v /etc/ssh/sshd_config..."
    if ! ssh -i "$key_path" -p "$port" -t \
             -o StrictHostKeyChecking=accept-new \
             "${new_user}@${host}" "sudo bash -s" <<<"$remote_script"; then
        print_warning "Config sa nepodarilo zmeniť — root zostáva aktívny. Skontroluj VPS manuálne."
        return 1
    fi

    print_success "PermitRootLogin no — sshd reštartovaný."
    return 0
}

# -----------------------------------------------------------------------------
# Verify that root login is really blocked
# -----------------------------------------------------------------------------
test_root_blocked() {
    local key_path="$1" host="$2" port="$3"
    print_info "Overujem že root login je zablokovaný..."
    if ssh -i "$key_path" -p "$port" \
           -o BatchMode=yes \
           -o ConnectTimeout=10 \
           -o PasswordAuthentication=no \
           -o StrictHostKeyChecking=accept-new \
           "root@${host}" "echo ok" 2>/dev/null | grep -q "^ok$"; then
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Final summary box (only on full success)
# -----------------------------------------------------------------------------
print_summary_box() {
    local new_user="$1" host="$2" port="$3"
    echo
    printf "${GREEN}╔════════════════════════════════════════════════╗${NC}\n"
    printf "${GREEN}║${NC}   ${BLUE}VCS Akadémia — Epizóda 02${NC}                    ${GREEN}║${NC}\n"
    printf "${GREEN}╠════════════════════════════════════════════════╣${NC}\n"
    printf "${GREEN}║${NC} ${GREEN}Hotovo!${NC}                                        ${GREEN}║${NC}\n"
    printf "${GREEN}║${NC} Prihlásenie: ssh -p %-5s %s@%s\n" "$port" "$new_user" "$host"
    printf "${GREEN}║${NC} Root login:  zablokovaný                       ${GREEN}║${NC}\n"
    printf "${GREEN}╚════════════════════════════════════════════════╝${NC}\n"
    echo
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
main() {
    printf "\n${BLUE}== VCS Akadémia — Epizóda 02: Sudo User + Zakáž Root Login ==${NC}\n\n"

    cat <<EOF
Tento skript urobí 6 krokov:
  1. Opýta sa na údaje VPS a meno nového používateľa.
  2. Vytvorí používateľa na VPS a pridá ho do skupiny sudo.
  3. Skopíruje tvoj SSH key na nového používateľa.
  4. Otestuje prihlásenie cez nového používateľa.
  5. Zakáže root login v sshd_config (len ak test v kroku 4 uspel).
  6. Overí že root login je skutočne zablokovaný.

Predpoklad: SSH key login ako root (Epizóda 01) už funguje.
EOF
    echo

    confirm "Chceš pokračovať?"

    printf "\n${BLUE}-- Kontrola závislostí --${NC}\n"
    check_dependencies
    print_success "ssh a ssh-keygen sú dostupné."

    local key_path="$HOME/.ssh/id_ed25519"
    if [ ! -f "$key_path" ]; then
        print_error "SSH key nenájdený ($key_path). Najprv spusti Epizódu 01."
    fi
    print_success "SSH key nájdený: $key_path"

    printf "\n${BLUE}-- Údaje o VPS --${NC}\n"
    local vps_host vps_port vps_user new_user
    vps_host="$(ask "IP adresa VPS" "")"
    if [ -z "$vps_host" ]; then
        print_error "IP adresa nesmie byť prázdna."
    fi
    vps_port="$(ask "SSH port" "22")"
    case "$vps_port" in
        ''|*[!0-9]*) print_error "Port musí byť číslo." ;;
    esac
    if [ "$vps_port" -lt 1 ] || [ "$vps_port" -gt 65535 ]; then
        print_error "Port musí byť v rozsahu 1–65535."
    fi
    vps_user="$(ask "Aktuálny user na VPS (cez koho sa pripájame)" "root")"

    new_user="$(ask "Meno nového sudo používateľa" "")"
    if [ -z "$new_user" ]; then
        print_error "Meno používateľa nesmie byť prázdne."
    fi
    if ! validate_username "$new_user"; then
        print_error "Nesprávne meno. Povolené: a-z, 0-9, pomlčka; min. 3 znaky; musí začínať písmenom."
    fi
    if [ "$new_user" = "root" ]; then
        print_error "Nový používateľ nemôže byť 'root'."
    fi

    echo
    print_info "Cieľ:          ${vps_user}@${vps_host}:${vps_port}"
    print_info "Nový user:     $new_user"
    print_info "Key path:      $key_path"
    echo
    confirm "Pokračovať s týmito údajmi?"

    printf "\n${BLUE}-- Krok 1/6 — Vytvorenie používateľa --${NC}\n"
    create_remote_user "$key_path" "$vps_user" "$vps_host" "$vps_port" "$new_user"

    printf "\n${BLUE}-- Krok 2/6 — Kopírovanie SSH key --${NC}\n"
    copy_authorized_keys "$key_path" "$vps_user" "$vps_host" "$vps_port" "$new_user"

    printf "\n${BLUE}-- Krok 3/6 — Test prihlásenia cez '%s' --${NC}\n" "$new_user"
    sleep 1
    if test_new_user_login "$key_path" "$vps_host" "$vps_port" "$new_user"; then
        print_success "Prihlásenie cez '$new_user' funguje."
    else
        print_warning "Prihlásenie cez '$new_user' zlyhalo."
        print_warning "Root zostáva aktívny — skript NEROBÍ zmeny v sshd_config."
        print_info    "Debug:  ssh -v -i $key_path -p $vps_port ${new_user}@${vps_host}"
        exit 1
    fi

    printf "\n${BLUE}-- Krok 4/6 — Zakázanie root loginu --${NC}\n"
    print_warning "Na VPS sa upraví /etc/ssh/sshd_config (PermitRootLogin no) a reštartuje sa sshd."
    confirm "Zakázať root login na VPS?"
    local harden_ok=1
    if disable_root_login "$key_path" "$vps_host" "$vps_port" "$new_user"; then
        harden_ok=0
    fi

    printf "\n${BLUE}-- Krok 5/6 — Overenie že root login je zablokovaný --${NC}\n"
    sleep 2
    if test_root_blocked "$key_path" "$vps_host" "$vps_port"; then
        print_success "Root login je zablokovaný."
    else
        print_warning "Root login stále funguje — skontroluj VPS manuálne."
        print_warning "Záloha: /etc/ssh/sshd_config.bak"
        exit 1
    fi

    if [ "$harden_ok" -ne 0 ]; then
        print_warning "sshd_config sa možno neupravil — overenie však hovorí, že root je zablokovaný. Skontroluj VPS."
    fi

    printf "\n${BLUE}-- Krok 6/6 — Hotovo --${NC}\n"
    print_summary_box "$new_user" "$vps_host" "$vps_port"
    print_info "Od tejto chvíle sa prihlasuj ako: ssh -p $vps_port ${new_user}@${vps_host}"
    print_info "Pre admin operácie použi: sudo <príkaz> (bez hesla)."
}

main "$@"

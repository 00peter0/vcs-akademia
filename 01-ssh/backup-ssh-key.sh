#!/usr/bin/env bash
# =============================================================================
# VCS Akadémia — Episode 01a: SSH Key Backup to USB
# -----------------------------------------------------------------------------
# YouTube:    youtube.com/@VCSAkademia
# GitHub:     github.com/VirtuCyberSecurity/vcs-akademia
#
# Usage (Mac/Linux terminal or Windows Git Bash):
#   curl -O https://raw.githubusercontent.com/VirtuCyberSecurity/vcs-akademia/main/01-ssh/backup-ssh-key.sh
#   bash backup-ssh-key.sh
#
# Windows users: install Git Bash from https://gitforwindows.org
# (ssh, ssh-keygen, ssh-copy-id and ~/.ssh all work the same as on Mac/Linux).
#
# This script runs LOCALLY on your computer. It:
#   1. Checks that an SSH key exists (~/.ssh/id_ed25519).
#   2. Detects connected USB devices.
#   3. Copies your SSH key pair to the selected USB.
#   4. Sets correct permissions on the backup.
#   5. Creates a README.txt with restore instructions.
#   6. Verifies the backup integrity.
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
# Detect USB devices based on OS
# -----------------------------------------------------------------------------
detect_usb_devices() {
    USB_DEVICES=()

    case "$OS" in
        mac)
            # List volumes, filter out system ones
            local skip_volumes="Macintosh HD|System|Preboot|Recovery|VM|Update"
            if [ -d "/Volumes" ]; then
                while IFS= read -r vol; do
                    local name
                    name="$(basename "$vol")"
                    if ! echo "$name" | grep -qE "^($skip_volumes)$"; then
                        USB_DEVICES+=("$vol")
                    fi
                done < <(find /Volumes -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
            fi
            ;;
        linux)
            # Check /media/$USER/ first, then /mnt/
            if [ -d "/media/$USER" ]; then
                while IFS= read -r dev; do
                    USB_DEVICES+=("$dev")
                done < <(find "/media/$USER" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
            fi
            if [ -d "/mnt" ]; then
                while IFS= read -r dev; do
                    # Only add if something is actually mounted there
                    if mountpoint -q "$dev" 2>/dev/null; then
                        USB_DEVICES+=("$dev")
                    fi
                done < <(find /mnt -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
            fi
            # Show lsblk info if available
            if command -v lsblk >/dev/null 2>&1; then
                print_info "Pripojené zariadenia:"
                lsblk -o NAME,MOUNTPOINT,SIZE,LABEL 2>/dev/null || true
                echo
            fi
            ;;
        windows)
            # In Git Bash, drives are mounted under /mnt/ or /
            # Skip c and d (typically internal), show e, f, g, etc.
            local internal_drives="c|d"
            for letter in /mnt/[a-z]; do
                if [ -d "$letter" ]; then
                    local drive_letter
                    drive_letter="$(basename "$letter")"
                    if ! echo "$drive_letter" | grep -qE "^($internal_drives)$"; then
                        USB_DEVICES+=("$letter")
                    fi
                fi
            done
            # Also check root-level drive mounts (some Git Bash versions)
            for letter in /[a-z]; do
                if [ -d "$letter" ] && [ "$letter" != "/c" ] && [ "$letter" != "/d" ]; then
                    # Avoid duplicates
                    local already_added=false
                    for existing in "${USB_DEVICES[@]+"${USB_DEVICES[@]}"}"; do
                        if [ "$existing" = "$letter" ]; then
                            already_added=true
                            break
                        fi
                    done
                    if [ "$already_added" = false ]; then
                        USB_DEVICES+=("$letter")
                    fi
                fi
            done
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Summary box (dynamic width)
# -----------------------------------------------------------------------------
print_summary_box() {
    local title="VCS Akadémia — Epizóda 01a"
    local -a lines=("$@")

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
        if [ -z "$line" ]; then
            printf "${GREEN}║${NC}%*s${GREEN}║${NC}\n" $((width + 1)) ""
        else
            printf "${GREEN}║${NC} %s%*s${GREEN}║${NC}\n" "$line" $((width - ${#line} - 1)) ""
        fi
    done
    printf "${GREEN}╚%s╝${NC}\n" "$border"
    echo
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
main() {
    printf "\n${BLUE}== VCS Akadémia — Epizóda 01a: Záloha SSH kľúča na USB ==${NC}\n\n"

    print_info "Tento skript zálohuje tvoj SSH kľúč na USB zariadenie."
    print_info "Zálohu drž na bezpečnom mieste — oddelene od počítača."
    echo

    confirm "Chceš pokračovať?"

    # -- Step 1: Check SSH key exists --
    printf "\n${BLUE}-- Krok 1/6 — Kontrola SSH kľúča --${NC}\n"
    local key_path="$HOME/.ssh/id_ed25519"

    if [ ! -f "$key_path" ]; then
        print_error "SSH kľúč nenájdený (~/.ssh/id_ed25519)
Najprv spusti epizódu 01 — setup-keylogin.sh"
    fi
    print_success "SSH kľúč nájdený: $key_path"

    if [ ! -f "${key_path}.pub" ]; then
        print_error "Verejný kľúč nenájdený (~/.ssh/id_ed25519.pub)
Najprv spusti epizódu 01 — setup-keylogin.sh"
    fi
    print_success "Verejný kľúč nájdený: ${key_path}.pub"

    # -- Step 2: Detect USB devices --
    printf "\n${BLUE}-- Krok 2/6 — Detekcia USB zariadení --${NC}\n"
    detect_usb_devices

    if [ ${#USB_DEVICES[@]} -eq 0 ]; then
        print_error "Žiadne USB zariadenie nenájdené.
Pripoj USB a spusti skript znova."
    fi

    # -- Step 3: Select USB device --
    printf "\n${BLUE}-- Krok 3/6 — Výber USB zariadenia --${NC}\n"
    print_info "Dostupné USB zariadenia:"
    echo
    local i=1
    for dev in "${USB_DEVICES[@]}"; do
        local dev_name
        dev_name="$(basename "$dev")"
        printf "  ${GREEN}%d)${NC} %s (%s)\n" "$i" "$dev" "$dev_name"
        i=$((i + 1))
    done
    echo

    local usb_choice
    printf "${YELLOW}Vyber číslo zariadenia [1-%d]:${NC} " "${#USB_DEVICES[@]}"
    read -r usb_choice </dev/tty

    # Validate choice
    case "$usb_choice" in
        ''|*[!0-9]*)
            print_error "Neplatný výber — musíš zadať číslo."
            ;;
    esac
    if [ "$usb_choice" -lt 1 ] || [ "$usb_choice" -gt "${#USB_DEVICES[@]}" ]; then
        print_error "Číslo mimo rozsahu — vyber 1 až ${#USB_DEVICES[@]}."
    fi

    local usb_path="${USB_DEVICES[$((usb_choice - 1))]}"
    print_success "Vybrané zariadenie: $usb_path"

    # -- Step 4: Create backup directory --
    printf "\n${BLUE}-- Krok 4/6 — Vytvorenie zálohy --${NC}\n"
    local backup_dir="$usb_path/vcs-akademia-ssh-backup/$(date +%Y-%m-%d)"

    if [ -d "$backup_dir" ]; then
        print_warning "Záloha z dnešného dňa už existuje: $backup_dir"
        confirm "Prepísať existujúcu zálohu?"
    fi

    if ! mkdir -p "$backup_dir"; then
        print_error "Nepodarilo sa vytvoriť adresár: $backup_dir"
    fi
    print_success "Adresár vytvorený: $backup_dir"

    # Copy keys
    if ! cp "$key_path" "$backup_dir/id_ed25519"; then
        print_error "Nepodarilo sa skopírovať privátny kľúč."
    fi
    if ! cp "${key_path}.pub" "$backup_dir/id_ed25519.pub"; then
        print_error "Nepodarilo sa skopírovať verejný kľúč."
    fi
    print_success "SSH kľúče skopírované."

    # -- Step 5: Set permissions --
    printf "\n${BLUE}-- Krok 5/6 — Nastavenie práv --${NC}\n"
    chmod 600 "$backup_dir/id_ed25519" 2>/dev/null || print_warning "Nepodarilo sa nastaviť práva na privátnom kľúči (USB môže byť FAT32)."
    chmod 644 "$backup_dir/id_ed25519.pub" 2>/dev/null || print_warning "Nepodarilo sa nastaviť práva na verejnom kľúči (USB môže byť FAT32)."
    print_success "Práva nastavené."

    # -- Create README.txt on USB --
    cat > "$backup_dir/README.txt" <<README_EOF
VCS Akademia — SSH Key Backup
Date: $(date +"%Y-%m-%d %H:%M")

Files:
- id_ed25519      — PRIVATE key (NEVER share this)
- id_ed25519.pub  — public key (safe to share)

How to restore:
  cp id_ed25519 ~/.ssh/id_ed25519
  cp id_ed25519.pub ~/.ssh/id_ed25519.pub
  chmod 600 ~/.ssh/id_ed25519
  chmod 644 ~/.ssh/id_ed25519.pub

VCS Akademia: github.com/VirtuCyberSecurity/vcs-akademia
README_EOF
    print_success "README.txt vytvorený."

    # -- Step 6: Verify backup --
    printf "\n${BLUE}-- Krok 6/6 — Overenie zálohy --${NC}\n"
    local verify_ok=true

    if [ -s "$backup_dir/id_ed25519" ]; then
        print_success "id_ed25519 — OK"
    else
        print_error "id_ed25519 — súbor je prázdny alebo chýba. Záloha je poškodená."
        verify_ok=false
    fi

    if [ -s "$backup_dir/id_ed25519.pub" ]; then
        print_success "id_ed25519.pub — OK"
    else
        print_error "id_ed25519.pub — súbor je prázdny alebo chýba. Záloha je poškodená."
        verify_ok=false
    fi

    if [ -s "$backup_dir/README.txt" ]; then
        print_success "README.txt — OK"
    else
        print_warning "README.txt — chýba alebo je prázdny (nekritické)."
    fi

    if [ "$verify_ok" = false ]; then
        print_error "Záloha je poškodená — skontroluj USB a skús znova."
    fi

    print_success "Záloha overená — všetky súbory sú v poriadku."

    # -- Summary --
    print_summary_box \
        "SSH kľúč zálohovaný" \
        "Umiestnenie: $backup_dir" \
        "" \
        "Zálohované súbory:" \
        "  id_ed25519     — privátny kľúč" \
        "  id_ed25519.pub — verejný kľúč" \
        "  README.txt     — návod na obnovu" \
        "" \
        "USB drž na bezpečnom mieste" \
        "oddelene od počítača."

    print_warning "NIKDY nezdieľaj id_ed25519 — je to tvoj privátny kľúč."
    print_warning "id_ed25519.pub je verejný — ten zdieľať môžeš."
}

main "$@"

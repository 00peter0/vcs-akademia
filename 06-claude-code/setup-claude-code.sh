#!/usr/bin/env bash
# =============================================================================
# VCS Akadémia — Episode 06: Claude Code Agent
# -----------------------------------------------------------------------------
# YouTube:    youtube.com/@VCSAkademia
# GitHub:     github.com/VirtuCyberSecurity/vcs-akademia
#
# Usage (Mac/Linux terminal or Windows Git Bash):
#   curl -O https://raw.githubusercontent.com/00peter0/vcs-akademia/main/06-claude-code/setup-claude-code.sh
#   bash setup-claude-code.sh
#
# Windows users: install Git Bash from https://gitforwindows.org
# (ssh works the same as on Mac/Linux).
#
# This script runs LOCALLY on your computer. It:
#   1. Asks for VPS details and an optional project folder path.
#   2. Installs Node.js LTS on the VPS (if missing or version < 18).
#   3. Installs Claude Code CLI via npm (-g).
#   4. Optionally creates a project folder with a CLAUDE.md rules file.
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
# Yes/No prompt without exit on No (returns 0 for yes, 1 for no)
# -----------------------------------------------------------------------------
ask_yn() {
    local prompt="${1:-Pokračovať?}"
    local reply
    printf "${YELLOW}%s [y/N]:${NC} " "$prompt"
    read -r reply </dev/tty
    case "$reply" in
        y|Y|yes|YES|ano|ANO) return 0 ;;
        *) return 1 ;;
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
# Validators
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
# Build the remote script that installs Node.js LTS (if missing or < 18).
# Runs with root privileges on the VPS.
# Outputs one of: NODE_ALREADY_OK | NODE_INSTALLED | NODE_FAILED
# -----------------------------------------------------------------------------
build_node_install_script() {
    cat <<'REMOTE_EOF'
set -e
export DEBIAN_FRONTEND=noninteractive

NODE_VERSION_MAJOR=0
if command -v node >/dev/null 2>&1; then
    NODE_VERSION_MAJOR=$(node --version 2>/dev/null | sed 's/^v//' | cut -d'.' -f1)
    case "$NODE_VERSION_MAJOR" in
        ''|*[!0-9]*) NODE_VERSION_MAJOR=0 ;;
    esac
fi

if [ "$NODE_VERSION_MAJOR" -ge 18 ] 2>/dev/null; then
    echo "NODE_ALREADY_OK $(node --version)"
    exit 0
fi

if ! command -v curl >/dev/null 2>&1; then
    apt-get update -qq
    apt-get install -y curl ca-certificates
fi

curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - >/dev/null 2>&1 || {
    echo "NODE_FAILED setup_lts"
    exit 1
}

apt-get install -y nodejs >/dev/null 2>&1 || {
    echo "NODE_FAILED apt_install"
    exit 1
}

if ! command -v node >/dev/null 2>&1; then
    echo "NODE_FAILED not_found_after_install"
    exit 1
fi

echo "NODE_INSTALLED $(node --version)"
REMOTE_EOF
}

# -----------------------------------------------------------------------------
# Build the remote script that installs Claude Code CLI via npm.
# Outputs one of: CLAUDE_ALREADY_OK | CLAUDE_INSTALLED | CLAUDE_FAILED
# -----------------------------------------------------------------------------
build_claude_install_script() {
    cat <<'REMOTE_EOF'
set -e

if command -v claude >/dev/null 2>&1; then
    echo "CLAUDE_ALREADY_OK $(claude --version 2>/dev/null || echo 'unknown')"
    exit 0
fi

if ! command -v npm >/dev/null 2>&1; then
    echo "CLAUDE_FAILED npm_missing"
    exit 1
fi

npm install -g @anthropic-ai/claude-code >/dev/null 2>&1 || {
    echo "CLAUDE_FAILED npm_install"
    exit 1
}

if ! command -v claude >/dev/null 2>&1; then
    echo "CLAUDE_FAILED not_found_after_install"
    exit 1
fi

echo "CLAUDE_INSTALLED $(claude --version 2>/dev/null || echo 'unknown')"
REMOTE_EOF
}

# -----------------------------------------------------------------------------
# Build the remote script that creates a project folder with CLAUDE.md.
# Runs as the SSH user (sudo not required — created in user's HOME).
# -----------------------------------------------------------------------------
build_project_script() {
    local project_path="$1"
    cat <<REMOTE_EOF
set -e

PROJECT_DIR="${project_path}"
case "\$PROJECT_DIR" in
    "~"|"~/"*) PROJECT_DIR="\$HOME\${PROJECT_DIR#\~}" ;;
esac

mkdir -p "\$PROJECT_DIR"

if [ ! -f "\$PROJECT_DIR/CLAUDE.md" ]; then
    cat > "\$PROJECT_DIR/CLAUDE.md" <<'CLAUDE_MD_EOF'
# Claude Code — VCS Akadémia

## Pravidlá
- Vždy použi slovenčinu pri komunikácii
- Pred každou zmenou súboru ho najprv prečítaj
- Nikdy nerob git push — iba commit
- Pri deštruktívnych akciách sa opýtaj na potvrdenie
CLAUDE_MD_EOF
    echo "PROJECT_CREATED \$PROJECT_DIR"
else
    echo "PROJECT_EXISTS \$PROJECT_DIR"
fi
REMOTE_EOF
}

# -----------------------------------------------------------------------------
# Run a remote bash script via SSH, capture output + exit code.
# Usage: run_remote USER HOST PORT SUDO_PREFIX SCRIPT
# -----------------------------------------------------------------------------
run_remote() {
    local user="$1" host="$2" port="$3" sudo_prefix="$4" script="$5"
    ssh -p "$port" \
        -o StrictHostKeyChecking=accept-new \
        -o ConnectTimeout=15 \
        "${user}@${host}" "${sudo_prefix}bash -s" <<<"$script" 2>&1
}

# -----------------------------------------------------------------------------
# Install Node.js LTS on the VPS
# -----------------------------------------------------------------------------
install_node_remote() {
    local user="$1" host="$2" port="$3" sudo_prefix="$4"

    print_info "Kontrolujem / inštalujem Node.js LTS..."
    local script output
    script="$(build_node_install_script)"

    if ! output=$(run_remote "$user" "$host" "$port" "$sudo_prefix" "$script"); then
        printf "%s\n" "$output" >&2
        print_error "Inštalácia Node.js zlyhala."
    fi

    local last_line
    last_line=$(printf "%s" "$output" | tail -n1)
    case "$last_line" in
        NODE_ALREADY_OK*)
            print_success "Node.js už nainštalovaný (${last_line#NODE_ALREADY_OK })."
            ;;
        NODE_INSTALLED*)
            print_success "Node.js ${last_line#NODE_INSTALLED } nainštalovaný."
            ;;
        *)
            printf "%s\n" "$output" >&2
            print_error "Inštalácia Node.js zlyhala (neočakávaný výstup)."
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Install Claude Code CLI on the VPS
# -----------------------------------------------------------------------------
install_claude_remote() {
    local user="$1" host="$2" port="$3" sudo_prefix="$4"

    print_info "Inštalujem Claude Code CLI cez npm..."
    local script output
    script="$(build_claude_install_script)"

    if ! output=$(run_remote "$user" "$host" "$port" "$sudo_prefix" "$script"); then
        printf "%s\n" "$output" >&2
        print_error "Inštalácia Claude Code zlyhala (npm install -g @anthropic-ai/claude-code)."
    fi

    local last_line
    last_line=$(printf "%s" "$output" | tail -n1)
    case "$last_line" in
        CLAUDE_ALREADY_OK*)
            print_success "Claude Code už nainštalovaný (verzia ${last_line#CLAUDE_ALREADY_OK })."
            ;;
        CLAUDE_INSTALLED*)
            print_success "Claude Code ${last_line#CLAUDE_INSTALLED } nainštalovaný."
            ;;
        *)
            printf "%s\n" "$output" >&2
            print_error "Inštalácia Claude Code zlyhala (neočakávaný výstup)."
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Create the project folder + CLAUDE.md on the VPS (no sudo — user's HOME).
# -----------------------------------------------------------------------------
create_project_remote() {
    local user="$1" host="$2" port="$3" project_path="$4"

    print_info "Vytváram projekt folder: ${project_path}..."
    local script output
    script="$(build_project_script "$project_path")"

    if ! output=$(run_remote "$user" "$host" "$port" "" "$script"); then
        printf "%s\n" "$output" >&2
        print_warning "Vytvorenie projekt foldra zlyhalo — môžeš ho vytvoriť manuálne."
        return 1
    fi

    local last_line
    last_line=$(printf "%s" "$output" | tail -n1)
    case "$last_line" in
        PROJECT_CREATED*)
            print_success "Projekt folder vytvorený: ${last_line#PROJECT_CREATED }"
            print_success "CLAUDE.md vytvorený s pravidlami pre agenta."
            ;;
        PROJECT_EXISTS*)
            print_info "Projekt folder už existoval (${last_line#PROJECT_EXISTS }) — CLAUDE.md ponechaný."
            ;;
        *)
            printf "%s\n" "$output" >&2
            print_warning "Neočakávaný výstup pri vytváraní projektu."
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Final summary box (dynamic width)
# -----------------------------------------------------------------------------
print_summary_box() {
    local user="$1" host="$2" port="$3" project_path="$4"

    local version
    version=$(ssh -o BatchMode=yes \
                  -o StrictHostKeyChecking=accept-new \
                  -o ConnectTimeout=10 \
                  -p "$port" "${user}@${host}" \
                  'claude --version 2>/dev/null || echo "nainštalovaný"' 2>/dev/null)
    [ -z "$version" ] && version="nainštalovaný"

    local title="VCS Akadémia — Epizóda 06"
    local lines=(
        "Claude Code ${version}"
    )
    if [ -n "$project_path" ]; then
        lines+=("Projekt: ${project_path}")
    fi
    lines+=(
        ""
        "Posledný krok — prihlásenie:"
        "1. ssh -p ${port} ${user}@${host}"
        "2. claude"
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
    printf "\n${BLUE}== VCS Akadémia — Epizóda 06: Claude Code Agent ==${NC}\n\n"

    cat <<EOF
Tento skript nainštaluje Claude Code na tvoj VPS:
  1. Node.js LTS (cez NodeSource)
  2. Claude Code CLI (npm install -g @anthropic-ai/claude-code)
  3. Voliteľne projekt folder s CLAUDE.md
  4. Zobrazí inštrukcie na manuálne prihlásenie
EOF
    echo

    print_warning "Tento skript inštaluje balíky na VPS (Node.js, npm package globálne)."
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

    local create_project="n"
    local project_path=""
    if ask_yn "Vytvoriť projekt folder s CLAUDE.md?"; then
        create_project="y"
        project_path="$(ask "Cesta k projekt folderu" "~/claude-projects")"
        if [ -z "$project_path" ]; then
            print_error "Cesta k projektu nesmie byť prázdna."
        fi
    fi

    local sudo_prefix=""
    if [ "$vps_user" != "root" ]; then
        sudo_prefix="sudo "
        print_warning "Pripájaš sa ako '$vps_user' — na VPS sa použije sudo (možno si vyžiada heslo)."
    fi

    echo
    printf "${BLUE}-- Zhrnutie --${NC}\n"
    print_info "Cieľ:        ${vps_user}@${vps_host}:${vps_port}"
    if [ "$create_project" = "y" ]; then
        print_info "Projekt:     ${project_path}"
    else
        print_info "Projekt:     (neaktívne)"
    fi
    echo
    confirm "Pokračovať?"

    printf "\n${BLUE}-- Krok 1/3 — Node.js LTS --${NC}\n"
    install_node_remote "$vps_user" "$vps_host" "$vps_port" "$sudo_prefix"

    printf "\n${BLUE}-- Krok 2/3 — Claude Code CLI --${NC}\n"
    install_claude_remote "$vps_user" "$vps_host" "$vps_port" "$sudo_prefix"

    if [ "$create_project" = "y" ]; then
        printf "\n${BLUE}-- Krok 3/3 — Projekt folder --${NC}\n"
        create_project_remote "$vps_user" "$vps_host" "$vps_port" "$project_path" || true
    else
        printf "\n${BLUE}-- Krok 3/3 — Projekt folder (preskočené) --${NC}\n"
        print_info "Projekt folder nebol vytvorený — preskakujem."
    fi

    echo
    if [ "$create_project" = "y" ]; then
        print_success "Claude Code nainštalovaný a projekt folder pripravený."
    else
        print_success "Claude Code nainštalovaný."
    fi
    echo

    print_summary_box "$vps_user" "$vps_host" "$vps_port" \
                      "$([ "$create_project" = "y" ] && echo "$project_path" || echo "")"

    print_info "Ak chceš nechať agenta bežať aj po zatvorení SSH — pozri epizódu 07 (tmux)."
}

main "$@"

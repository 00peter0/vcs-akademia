#!/usr/bin/env bash
# =============================================================================
# VCS Akadémia — Episode 08: Agent Setup (cez SSH na VPS)
# -----------------------------------------------------------------------------
# YouTube:    youtube.com/@VCSAkademia
# GitHub:     github.com/VirtuCyberSecurity/vcs-akademia
#
# Usage (Mac/Linux terminal or Windows Git Bash):
#   curl -O https://raw.githubusercontent.com/00peter0/vcs-akademia/main/08-agent-setup/setup-agent.sh
#   bash setup-agent.sh
#
# Windows users: install Git Bash from https://gitforwindows.org
# (ssh works the same as on Mac/Linux).
#
# This script runs LOCALLY on your computer. It connects to your VPS via SSH
# and creates the Claude Code agent onboarding files (CLAUDE.md, PROJECT.md,
# TASKS.md, CHANGELOG.md + prompts) directly on the VPS using curl on the VPS.
# Nothing is downloaded to your local machine.
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
# Prompts
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

# Reject inputs that would break shell or sed escaping. Whitelisted chars only.
validate_input() {
    local label="$1" value="$2"
    case "$value" in
        *\"*|*\'*|*\$*|*\`*|*\\*|*\|*)
            print_error "$label obsahuje nepovolený znak (\" ' \\ \$ \` |). Použi jednoduchý text."
            ;;
    esac
    case "$value" in
        *$'\n'*|*$'\r'*) print_error "$label nesmie obsahovať nový riadok." ;;
    esac
}

# -----------------------------------------------------------------------------
# Local dependencies — only ssh and curl are needed locally.
# -----------------------------------------------------------------------------
check_local_dependencies() {
    local missing=""
    for tool in ssh curl; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing="${missing} ${tool}"
        fi
    done
    if [ -n "$missing" ]; then
        print_warning "Lokálne chýbajú nástroje:${missing}"
        case "$OS" in
            windows) print_info "Na Windows potrebuješ Git Bash: https://gitforwindows.org" ;;
            mac)     print_info "Na Mac sú štandardne dostupné (xcode-select --install)." ;;
            linux)   print_info "Na Debian/Ubuntu: sudo apt install openssh-client curl" ;;
        esac
        print_error "Doinštaluj chýbajúce nástroje a spusti skript znova."
    fi
}

# -----------------------------------------------------------------------------
# SSH wrapper — uses ControlMaster so we open ONE connection and reuse it
# for every check / mkdir / curl / sed call. Avoids re-prompting for password.
# -----------------------------------------------------------------------------
SSH_CTRL=""
SSH_TARGET=""
SSH_PORT_OPT=""

ssh_setup() {
    SSH_CTRL="${TMPDIR:-/tmp}/vcs-agent-ssh-$$"
    SSH_TARGET="${VPS_USER}@${VPS_IP}"
    SSH_PORT_OPT="-p ${VPS_PORT}"
    trap 'ssh -O exit -o ControlPath="$SSH_CTRL" "$SSH_TARGET" >/dev/null 2>&1 || true; rm -f "$SSH_CTRL"' EXIT
}

ssh_run() {
    # shellcheck disable=SC2086
    ssh $SSH_PORT_OPT \
        -o ControlMaster=auto \
        -o ControlPath="$SSH_CTRL" \
        -o ControlPersist=300 \
        -o StrictHostKeyChecking=accept-new \
        "$SSH_TARGET" "$@"
}

ssh_test_connection() {
    print_info "Testujem SSH spojenie na ${SSH_TARGET} (port ${VPS_PORT})..."
    if ! ssh_run "echo __vcs_ok__" | grep -q '^__vcs_ok__$'; then
        print_error "Pripojenie na VPS zlyhalo. Skontroluj IP, port, používateľa a SSH kľúč."
    fi
    print_success "SSH spojenie funguje."
}

# -----------------------------------------------------------------------------
# Remote helpers — every command runs on the VPS through ssh_run.
# -----------------------------------------------------------------------------
remote_home() {
    # Single quotes — don't expand $HOME locally.
    local home
    home=$(ssh_run 'printf %s "$HOME"') || print_error "Nepodarilo sa zistiť HOME na VPS."
    if [ -z "$home" ]; then
        print_error "VPS vrátil prázdny HOME."
    fi
    printf '%s' "$home"
}

remote_dir_exists() {
    local path="$1" out
    out=$(ssh_run "[ -d '$path' ] && echo exists || echo notfound") \
        || print_error "Kontrola adresára '$path' na VPS zlyhala."
    [ "$out" = "exists" ]
}

remote_file_exists() {
    local path="$1" out
    out=$(ssh_run "[ -f '$path' ] && echo exists || echo notfound") \
        || print_error "Kontrola súboru '$path' na VPS zlyhala."
    [ "$out" = "exists" ]
}

remote_mkdir() {
    local path="$1"
    ssh_run "mkdir -p '$path'" || print_error "Vytvorenie adresára '$path' na VPS zlyhalo."
}

# Download a single file via curl ON THE VPS. Aborts on HTTP error or empty body.
remote_curl() {
    local url="$1" dest="$2"
    if ! ssh_run "curl -fsSL '$url' -o '$dest'"; then
        print_error "Sťahovanie zlyhalo na VPS: $url"
    fi
    if ! ssh_run "[ -s '$dest' ]"; then
        print_error "Stiahnutý súbor je prázdny: $dest"
    fi
}

# In-place sed on the VPS. Two modes: "all" or "first".
# Pattern is the literal placeholder text (we escape regex metas).
# Replacement gets \, &, and | escaped (we use | as the sed delimiter).
remote_replace() {
    local file="$1" search="$2" replace="$3" mode="${4:-all}"
    local pat rep

    pat=$(printf '%s' "$search"  | sed -e 's/[]\/$*.^[\\|&{}()?+]/\\&/g')
    rep=$(printf '%s' "$replace" | sed -e 's/[\\&|]/\\&/g')

    if [ "$mode" = "first" ]; then
        ssh_run "sed -i \"0,/${pat}/s|${pat}|${rep}|\" '$file'" \
            || print_error "Úprava (first) zlyhala v súbore: $file"
    else
        ssh_run "sed -i \"s|${pat}|${rep}|g\" '$file'" \
            || print_error "Úprava zlyhala v súbore: $file"
    fi
}

# -----------------------------------------------------------------------------
# Final summary box (dynamic width — same style as 01-ssh).
# -----------------------------------------------------------------------------
print_summary_box() {
    local title="VCS Akadémia — Epizóda 08"
    local ssh_cmd
    if [ "$VPS_PORT" = "22" ]; then
        ssh_cmd="ssh ${VPS_USER}@${VPS_IP}"
    else
        ssh_cmd="ssh -p ${VPS_PORT} ${VPS_USER}@${VPS_IP}"
    fi

    local lines=(
        "Agent súbory vytvorené na VPS"
        "Projekt: ${PROJECT_NAME}"
        "Umiestnenie: ${VPS_USER}@${VPS_IP}:${PROJECT_PATH}"
        ""
        "Ďalší krok:"
        "  ${ssh_cmd}"
        "  cd ${PROJECT_PATH} && claude"
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
# Constants
# -----------------------------------------------------------------------------
BASE_URL="https://raw.githubusercontent.com/00peter0/vcs-akademia/main/08-agent-setup/templates"
TEMPLATE_FILES="CLAUDE.md PROJECT.md TASKS.md CHANGELOG.md"
PROMPT_FILES="new-feature.md fix-bug.md code-review.md deploy.md"

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
main() {
    printf "\n${BLUE}== VCS Akadémia — Epizóda 08: Nastavenie Claude Code Agenta na VPS ==${NC}\n\n"

    cat <<EOF
Tento skript beží lokálne. Pripojí sa cez SSH na tvoj VPS a tam:
  1. Skontroluje / vytvorí adresár projektu.
  2. Stiahne šablóny (CLAUDE.md, PROJECT.md, TASKS.md, CHANGELOG.md + prompty)
     priamo na VPS cez curl.
  3. Vyplní základné info (názov, popis, stack, dátum).
  4. Vypíše čo treba doplniť manuálne.

Lokálne sa nič nesťahuje.
EOF
    echo
    confirm "Chceš pokračovať?"

    printf "\n${BLUE}-- Kontrola lokálnych závislostí --${NC}\n"
    check_local_dependencies
    print_success "ssh a curl sú dostupné lokálne."

    # -------------------------------------------------------------------------
    # Inputs
    # -------------------------------------------------------------------------
    printf "\n${BLUE}-- Údaje o VPS --${NC}\n"
    VPS_IP="$(ask "IP adresa VPS" "")"
    if [ -z "$VPS_IP" ]; then
        print_error "IP adresa nesmie byť prázdna."
    fi
    validate_input "IP adresa" "$VPS_IP"

    VPS_PORT="$(ask "SSH port" "22")"
    case "$VPS_PORT" in
        ''|*[!0-9]*) print_error "Port musí byť číslo." ;;
    esac
    if [ "$VPS_PORT" -lt 1 ] || [ "$VPS_PORT" -gt 65535 ]; then
        print_error "Port musí byť v rozsahu 1–65535."
    fi

    VPS_USER="$(ask "Username na VPS" "root")"
    if [ -z "$VPS_USER" ]; then
        print_error "Username nesmie byť prázdny."
    fi
    validate_input "Username" "$VPS_USER"

    printf "\n${BLUE}-- Údaje o projekte --${NC}\n"
    PROJECT_PATH="$(ask "Cesta k projektu na VPS" "~/projects")"
    if [ -z "$PROJECT_PATH" ]; then
        print_error "Cesta nesmie byť prázdna."
    fi
    validate_input "Cesta k projektu" "$PROJECT_PATH"

    PROJECT_NAME="$(ask "Názov projektu" "")"
    if [ -z "$PROJECT_NAME" ]; then
        print_error "Názov projektu nesmie byť prázdny."
    fi
    validate_input "Názov projektu" "$PROJECT_NAME"

    PROJECT_DESC="$(ask "Krátky popis projektu (1-2 vety)" "")"
    if [ -z "$PROJECT_DESC" ]; then
        print_error "Popis projektu nesmie byť prázdny."
    fi
    validate_input "Popis projektu" "$PROJECT_DESC"

    PROJECT_STACK="$(ask "Stack (napr. bash, Go, Python, Node.js)" "")"
    if [ -z "$PROJECT_STACK" ]; then
        PROJECT_STACK="[doplň]"
    else
        validate_input "Stack" "$PROJECT_STACK"
    fi

    # -------------------------------------------------------------------------
    # Open SSH connection (ControlMaster) and resolve remote HOME
    # -------------------------------------------------------------------------
    printf "\n${BLUE}-- Pripojenie na VPS --${NC}\n"
    ssh_setup
    ssh_test_connection

    local rhome
    rhome=$(remote_home)
    case "$PROJECT_PATH" in
        "~")    PROJECT_PATH="$rhome" ;;
        "~/"*)  PROJECT_PATH="${rhome}/${PROJECT_PATH#\~/}" ;;
    esac

    echo
    printf "${BLUE}-- Zhrnutie --${NC}\n"
    print_info "VPS:        ${VPS_USER}@${VPS_IP}:${VPS_PORT}"
    print_info "Cesta:      ${PROJECT_PATH}"
    print_info "Projekt:    ${PROJECT_NAME}"
    print_info "Popis:      ${PROJECT_DESC}"
    print_info "Stack:      ${PROJECT_STACK}"
    echo
    confirm "Pokračovať s týmito údajmi?"

    # -------------------------------------------------------------------------
    # Ensure project dir exists on VPS
    # -------------------------------------------------------------------------
    printf "\n${BLUE}-- Adresár projektu na VPS --${NC}\n"
    if remote_dir_exists "$PROJECT_PATH"; then
        print_info "Adresár '$PROJECT_PATH' už existuje na VPS."
    else
        print_warning "Adresár '$PROJECT_PATH' na VPS neexistuje — vytvorím ho."
        remote_mkdir "$PROJECT_PATH"
        print_success "Adresár vytvorený."
    fi

    # -------------------------------------------------------------------------
    # Download templates onto the VPS via curl-on-VPS
    # -------------------------------------------------------------------------
    printf "\n${BLUE}-- Sťahujem šablóny na VPS --${NC}\n"

    local skip_list=""
    for f in $TEMPLATE_FILES; do
        local dest="${PROJECT_PATH}/${f}"
        if remote_file_exists "$dest"; then
            print_warning "${f} už existuje — preskakujem."
            skip_list="${skip_list} ${f}"
            continue
        fi
        print_info "Sťahujem ${f} na VPS..."
        remote_curl "${BASE_URL}/${f}" "$dest"
    done

    local prompts_dir="${PROJECT_PATH}/.claude/prompts"
    print_info "Vytváram ${prompts_dir} na VPS..."
    remote_mkdir "$prompts_dir"

    for p in $PROMPT_FILES; do
        local dest="${prompts_dir}/${p}"
        if remote_file_exists "$dest"; then
            print_warning ".claude/prompts/${p} už existuje — preskakujem."
            continue
        fi
        print_info "Sťahujem .claude/prompts/${p} na VPS..."
        remote_curl "${BASE_URL}/prompts/${p}" "$dest"
    done

    print_success "Šablóny stiahnuté na VPS."

    # -------------------------------------------------------------------------
    # Fill placeholders on VPS via sed
    # -------------------------------------------------------------------------
    printf "\n${BLUE}-- Vypĺňam placeholders na VPS --${NC}\n"

    for f in $TEMPLATE_FILES; do
        case " $skip_list " in
            *" $f "*) continue ;;
        esac
        local file="${PROJECT_PATH}/${f}"
        remote_replace "$file" "[Názov projektu]" "$PROJECT_NAME" "all"
        remote_replace "$file" "[Doplň: krátky popis projektu v 1-2 vetách]" "$PROJECT_DESC" "all"
        remote_replace "$file" "[Doplň: 1-2 vety čo projekt robí]" "$PROJECT_DESC" "all"
        # Stack: only the FIRST [doplň] occurrence
        remote_replace "$file" "[doplň]" "$PROJECT_STACK" "first"
    done

    # CHANGELOG date
    case " $skip_list " in
        *" CHANGELOG.md "*) : ;;
        *)
            local today
            today=$(date +%Y-%m-%d)
            remote_replace "${PROJECT_PATH}/CHANGELOG.md" "[dátum]" "$today" "all"
            ;;
    esac

    print_success "Placeholders vyplnené."

    # -------------------------------------------------------------------------
    # Manual TODO hints
    # -------------------------------------------------------------------------
    printf "\n${BLUE}-- Čo treba doplniť manuálne --${NC}\n"
    print_info "Otvor tieto súbory na VPS a doplň detaily:"
    print_info "  ${PROJECT_PATH}/CLAUDE.md                  → čo nesmie agent robiť"
    print_info "  ${PROJECT_PATH}/PROJECT.md                 → štruktúra, ako deploynúť"
    print_info "  ${PROJECT_PATH}/TASKS.md                   → prvé úlohy projektu"
    print_info "  ${PROJECT_PATH}/.claude/prompts/deploy.md  → tvoj deploy postup"

    print_summary_box
}

main "$@"

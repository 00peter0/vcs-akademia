#!/usr/bin/env bash
# =============================================================================
# VCS Akadémia — Episode 09: Agent Skills (cez SSH na VPS)
# -----------------------------------------------------------------------------
# YouTube:    youtube.com/@VCSAkademia
# GitHub:     github.com/VirtuCyberSecurity/vcs-akademia
#
# Usage (Mac/Linux terminal or Windows Git Bash):
#   curl -O https://raw.githubusercontent.com/00peter0/vcs-akademia/main/09-agent-skills/setup-skills.sh
#   bash setup-skills.sh
#
# Windows users: install Git Bash from https://gitforwindows.org
# (ssh works the same as on Mac/Linux).
#
# This script runs LOCALLY on your computer. It connects to your VPS via SSH
# and installs Claude Code agent skills (docker / nginx / systemd / deploy /
# debug) into .claude/skills/ directly on the VPS using curl on the VPS.
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

ask_yn() {
    local prompt="${1:-Pokračovať?}"
    local default="${2:-n}"
    local reply hint
    case "$default" in
        y|Y) hint="[Y/n]" ;;
        *)   hint="[y/N]" ;;
    esac
    printf "${YELLOW}%s %s:${NC} " "$prompt" "$hint"
    read -r reply </dev/tty
    if [ -z "$reply" ]; then
        reply="$default"
    fi
    case "$reply" in
        y|Y|yes|YES|ano|ANO) return 0 ;;
        *) return 1 ;;
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

# Reject inputs that would break shell escaping. Whitelisted chars only.
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
# for every check / mkdir / curl call. Avoids re-prompting for password.
# -----------------------------------------------------------------------------
SSH_CTRL=""
SSH_TARGET=""
SSH_PORT_OPT=""

ssh_setup() {
    SSH_CTRL="${TMPDIR:-/tmp}/vcs-skills-ssh-$$"
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

# -----------------------------------------------------------------------------
# Final summary box (dynamic width — same style as 01-ssh / 08-agent-setup).
# -----------------------------------------------------------------------------
print_summary_box() {
    local installed="$1"
    local title="VCS Akadémia — Epizóda 09"

    local lines=(
        "Skills nainštalované na VPS"
        "Projekt: ${PROJECT_PATH}"
        "Server:  ${VPS_USER}@${VPS_IP}:${VPS_PORT}"
        ""
        "Nainštalované skills:"
    )
    local s
    for s in $installed; do
        lines+=("  ✓ $s")
    done
    lines+=("")
    lines+=("Šablóna pre nový skill:")
    lines+=("  .claude/skills/SKILL-TEMPLATE.md")

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
BASE_URL="https://raw.githubusercontent.com/00peter0/vcs-akademia/main/09-agent-skills/templates"
ALL_SKILLS="docker nginx systemd deploy debug"

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
main() {
    printf "\n${BLUE}== VCS Akadémia — Epizóda 09: Agent Skills na VPS ==${NC}\n\n"

    cat <<EOF
Tento skript beží lokálne. Pripojí sa cez SSH na tvoj VPS a tam:
  1. Overí že projekt existuje (CLAUDE.md).
  2. Stiahne SKILL-TEMPLATE.md + vybrané skills do .claude/skills/ na VPS.
  3. Aktualizuje CLAUDE.md na VPS — pridá sekciu '## Skills'.

Lokálne sa nič nesťahuje.
EOF
    echo
    confirm "Chceš pokračovať?"

    printf "\n${BLUE}-- Kontrola lokálnych závislostí --${NC}\n"
    check_local_dependencies
    print_success "ssh a curl sú dostupné lokálne."

    # -------------------------------------------------------------------------
    # VPS inputs
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

    # -------------------------------------------------------------------------
    # SSH connection
    # -------------------------------------------------------------------------
    printf "\n${BLUE}-- Pripojenie na VPS --${NC}\n"
    ssh_setup
    ssh_test_connection

    # Expand ~ on the remote side
    local rhome
    rhome=$(remote_home)
    case "$PROJECT_PATH" in
        "~")   PROJECT_PATH="$rhome" ;;
        "~/"*) PROJECT_PATH="${rhome}/${PROJECT_PATH#\~/}" ;;
    esac

    # -------------------------------------------------------------------------
    # Verify project on VPS
    # -------------------------------------------------------------------------
    printf "\n${BLUE}-- Overujem projekt na VPS --${NC}\n"
    if ! remote_dir_exists "$PROJECT_PATH"; then
        print_warning "Adresár '$PROJECT_PATH' na VPS neexistuje."
        if ! ask_yn "Vytvoriť ho a pokračovať aj tak?" "n"; then
            print_info "Zrušené."
            exit 0
        fi
        remote_mkdir "$PROJECT_PATH"
        print_success "Adresár vytvorený."
    fi

    if remote_file_exists "$PROJECT_PATH/CLAUDE.md"; then
        print_success "CLAUDE.md nájdený na VPS."
    else
        print_warning "CLAUDE.md nenájdený v '$PROJECT_PATH' — odporúčame najprv epizódu 08."
        if ! ask_yn "Pokračovať aj tak?" "n"; then
            print_info "Zrušené."
            exit 0
        fi
    fi

    # -------------------------------------------------------------------------
    # Skill choice
    # -------------------------------------------------------------------------
    printf "\n${BLUE}-- Výber skills --${NC}\n"
    print_info "Vyber skills (zadaj čísla oddelené medzerou, napr: 1 2 3):"
    print_info "  1) docker"
    print_info "  2) nginx"
    print_info "  3) systemd"
    print_info "  4) deploy"
    print_info "  5) debug"
    print_info "  6) všetky"
    echo
    printf "Tvoj výber: "
    local skill_choice
    read -r skill_choice </dev/tty

    if [ -z "$skill_choice" ]; then
        print_error "Nevybral si žiadne skills."
    fi

    local selected=""
    local n
    for n in $skill_choice; do
        case "$n" in
            1) selected="${selected} docker"  ;;
            2) selected="${selected} nginx"   ;;
            3) selected="${selected} systemd" ;;
            4) selected="${selected} deploy"  ;;
            5) selected="${selected} debug"   ;;
            6) selected="$ALL_SKILLS"; break  ;;
            *) print_warning "Neplatná voľba: '$n' — preskakujem." ;;
        esac
    done

    # Deduplicate (preserve order)
    local dedup="" s
    for s in $selected; do
        case " $dedup " in
            *" $s "*) : ;;
            *) dedup="${dedup} $s" ;;
        esac
    done
    selected="$(echo $dedup)"

    if [ -z "$selected" ]; then
        print_error "Žiadny platný skill nebol vybraný."
    fi

    echo
    printf "${BLUE}-- Zhrnutie --${NC}\n"
    print_info "VPS:     ${VPS_USER}@${VPS_IP}:${VPS_PORT}"
    print_info "Projekt: ${PROJECT_PATH}"
    print_info "Skills:  ${selected}"
    echo
    confirm "Pokračovať?"

    # -------------------------------------------------------------------------
    # Create skills directory on VPS
    # -------------------------------------------------------------------------
    printf "\n${BLUE}-- Pripravujem adresár na VPS --${NC}\n"
    local skills_dir="$PROJECT_PATH/.claude/skills"
    remote_mkdir "$skills_dir"
    print_success "Adresár pripravený: ${skills_dir}"

    # -------------------------------------------------------------------------
    # Download SKILL.md template onto VPS
    # -------------------------------------------------------------------------
    printf "\n${BLUE}-- Sťahujem šablónu pre nový skill --${NC}\n"
    local template_dest="$skills_dir/SKILL-TEMPLATE.md"
    if remote_file_exists "$template_dest"; then
        print_warning "SKILL-TEMPLATE.md už existuje — preskakujem."
    else
        remote_curl "$BASE_URL/SKILL.md" "$template_dest"
        print_success "Šablóna: .claude/skills/SKILL-TEMPLATE.md"
    fi

    # -------------------------------------------------------------------------
    # Download chosen skills onto VPS
    # -------------------------------------------------------------------------
    printf "\n${BLUE}-- Sťahujem vybrané skills na VPS --${NC}\n"
    local installed=""
    for s in $selected; do
        local skill_dir="$skills_dir/$s"
        local skill_file="$skill_dir/SKILL.md"
        if remote_file_exists "$skill_file"; then
            print_warning "$s už existuje — preskakujem."
        else
            remote_mkdir "$skill_dir"
            remote_curl "$BASE_URL/skills/$s/SKILL.md" "$skill_file"
            print_success "Skill nainštalovaný: $s"
        fi
        installed="${installed} $s"
    done
    installed="$(echo $installed)"

    # -------------------------------------------------------------------------
    # Update CLAUDE.md on VPS
    # -------------------------------------------------------------------------
    printf "\n${BLUE}-- Aktualizujem CLAUDE.md na VPS --${NC}\n"
    local claude_md="$PROJECT_PATH/CLAUDE.md"
    if ! remote_file_exists "$claude_md"; then
        print_warning "CLAUDE.md nenájdený — preskakujem aktualizáciu."
        print_info "Pridaj do CLAUDE.md ručne sekciu '## Skills' so zoznamom súborov."
    else
        local has_section
        has_section=$(ssh_run "grep -q '^## Skills' '$claude_md' && echo exists || echo missing") \
            || print_error "Kontrola CLAUDE.md zlyhala."
        if [ "$has_section" = "exists" ]; then
            print_info "Sekcia '## Skills' už existuje v CLAUDE.md."
        else
            {
                printf '\n## Skills\n'
                printf 'Pred prácou s týmito nástrojmi vždy prečítaj príslušný skill:\n'
                for s in $installed; do
                    printf -- '- %s: .claude/skills/%s/SKILL.md\n' "$s" "$s"
                done
            } | ssh_run "cat >> '$claude_md'" \
                || print_error "Zápis do CLAUDE.md na VPS zlyhal."
            print_success "CLAUDE.md aktualizovaný — sekcia '## Skills' pridaná."
        fi
    fi

    # -------------------------------------------------------------------------
    # Final summary
    # -------------------------------------------------------------------------
    print_summary_box "$installed"

    print_info "Ďalší krok:"
    print_info "  1. Prihlás sa na VPS: ssh ${VPS_USER}@${VPS_IP}"
    print_info "  2. cd ${PROJECT_PATH} && claude"
    print_info "  3. Pre vlastný skill skopíruj šablónu SKILL-TEMPLATE.md do .claude/skills/MOJ-SKILL/SKILL.md"
}

main "$@"

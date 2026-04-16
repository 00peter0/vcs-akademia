#!/usr/bin/env bash
# =============================================================================
# VCS Akadémia — Episode 09: Agent Skills
# -----------------------------------------------------------------------------
# YouTube:    youtube.com/@VCSAkademia
# GitHub:     github.com/VirtuCyberSecurity/vcs-akademia
#
# Usage (Mac/Linux terminal or Windows Git Bash):
#   curl -O https://raw.githubusercontent.com/00peter0/vcs-akademia/main/09-agent-skills/setup-skills.sh
#   bash setup-skills.sh
#
# Windows users: install Git Bash from https://gitforwindows.org
# (curl works the same as on Mac/Linux).
#
# This script runs LOCALLY on your computer. It:
#   1. Asks where your project is.
#   2. Lets you pick which skills to install (docker / nginx / systemd / deploy / debug).
#   3. Downloads SKILL.md template + chosen skills into .claude/skills/.
#   4. Updates CLAUDE.md so the agent knows the skills exist.
#
# It does NOT connect to any VPS.
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
# Confirmation prompt [y/N] — exits on No
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
# Yes/No prompt — returns 0 for yes, 1 for no (no exit)
# -----------------------------------------------------------------------------
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
    for tool in curl mkdir; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing="${missing} ${tool}"
        fi
    done
    if [ -n "$missing" ]; then
        print_warning "Chýbajúce nástroje:${missing}"
        case "$OS" in
            windows) print_info "Na Windows potrebuješ Git Bash: https://gitforwindows.org" ;;
            mac)     print_info "Na Mac by mali byť štandardne dostupné (xcode-select --install)." ;;
            linux)   print_info "Na Debian/Ubuntu: sudo apt install curl" ;;
        esac
        print_error "Doinštaluj chýbajúce nástroje a spusti skript znova."
    fi
}

# -----------------------------------------------------------------------------
# Download one file from GitHub.
# Usage: fetch_file URL DEST_PATH
# -----------------------------------------------------------------------------
BASE_URL="https://raw.githubusercontent.com/00peter0/vcs-akademia/main/09-agent-skills/templates"

fetch_file() {
    local url="$1" dest="$2"
    local http_code
    http_code=$(curl -sS -w '%{http_code}' -o "$dest" "$url" 2>/dev/null) || {
        print_error "Stiahnutie zlyhalo: ${url} (curl chyba)"
    }
    if [ "$http_code" != "200" ]; then
        rm -f "$dest"
        print_error "Stiahnutie zlyhalo: ${url} (HTTP ${http_code})"
    fi
    if [ ! -s "$dest" ]; then
        print_error "Stiahnutý súbor je prázdny: ${url}"
    fi
}

# -----------------------------------------------------------------------------
# Available skills (label : key)
# -----------------------------------------------------------------------------
ALL_SKILLS="docker nginx systemd deploy debug"

# -----------------------------------------------------------------------------
# Final summary box
# -----------------------------------------------------------------------------
print_summary_box() {
    local installed="$1" path="$2"
    echo
    printf "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}\n"
    printf "${GREEN}║${NC}   ${BLUE}VCS Akadémia — Epizóda 09${NC}                              ${GREEN}║${NC}\n"
    printf "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}\n"
    printf "${GREEN}║${NC} ${GREEN}Skills nainštalované${NC}                                     ${GREEN}║${NC}\n"
    printf "${GREEN}║${NC} Umiestnenie: %-44s${GREEN}║${NC}\n" ".claude/skills/"
    printf "${GREEN}║${NC} Projekt:     %-44s${GREEN}║${NC}\n" "$path"
    printf "${GREEN}║${NC}                                                          ${GREEN}║${NC}\n"
    printf "${GREEN}║${NC} Nainštalované skills:                                    ${GREEN}║${NC}\n"
    for s in $installed; do
        printf "${GREEN}║${NC}   - %-54s${GREEN}║${NC}\n" "$s"
    done
    printf "${GREEN}║${NC}                                                          ${GREEN}║${NC}\n"
    printf "${GREEN}║${NC} Šablóna pre nový skill:                                  ${GREEN}║${NC}\n"
    printf "${GREEN}║${NC}   .claude/skills/SKILL-TEMPLATE.md                       ${GREEN}║${NC}\n"
    printf "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}\n"
    echo
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
main() {
    printf "\n${BLUE}== VCS Akadémia — Epizóda 09: Agent Skills ==${NC}\n\n"

    cat <<EOF
Tento skript pridá Claude Code agentovi "skills" — návody pre konkrétne nástroje
a workflowy. Bez nich agent vymýšľa, so skillom vie presne čo robiť.

  1. Opýta sa kde je tvoj projekt.
  2. Necháš si vybrať ktoré skills chceš nainštalovať.
  3. Stiahne SKILL.md šablónu + vybrané skills do .claude/skills/.
  4. Aktualizuje CLAUDE.md aby agent o skills vedel.
EOF
    echo
    confirm "Chceš pokračovať?"

    printf "\n${BLUE}-- Kontrola závislostí --${NC}\n"
    check_dependencies
    print_success "Všetky potrebné nástroje sú dostupné."

    # -------------------------------------------------------------------------
    # Project path
    # -------------------------------------------------------------------------
    printf "\n${BLUE}-- Projekt --${NC}\n"

    local project_path
    project_path="$(ask "Cesta k projektu" "./")"
    if [ -z "$project_path" ]; then
        print_error "Cesta nesmie byť prázdna."
    fi

    # Expand leading ~ to $HOME
    case "$project_path" in
        "~")   project_path="$HOME" ;;
        "~/"*) project_path="$HOME/${project_path#~/}" ;;
    esac

    if [ ! -d "$project_path" ]; then
        print_error "Adresár '$project_path' neexistuje."
    fi

    # Normalize to absolute path (best-effort)
    local abs
    abs=$(cd "$project_path" 2>/dev/null && pwd) || abs="$project_path"
    project_path="$abs"

    # CLAUDE.md check (warning only)
    if [ ! -f "$project_path/CLAUDE.md" ]; then
        print_warning "Toto nevyzerá ako agent projekt (chýba CLAUDE.md). Odporúčame epizódu 08."
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

    # Resolve choice -> skill list
    local selected=""
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
    local dedup=""
    for s in $selected; do
        case " $dedup " in
            *" $s "*) : ;;
            *) dedup="${dedup} $s" ;;
        esac
    done
    selected="$(echo $dedup)"  # trim

    if [ -z "$selected" ]; then
        print_error "Žiadny platný skill nebol vybraný."
    fi

    echo
    printf "${BLUE}-- Zhrnutie --${NC}\n"
    print_info "Projekt:  ${project_path}"
    print_info "Skills:   ${selected}"
    echo
    confirm "Pokračovať?"

    # -------------------------------------------------------------------------
    # Create directory structure
    # -------------------------------------------------------------------------
    local skills_dir="$project_path/.claude/skills"
    mkdir -p "$skills_dir" || print_error "Vytvorenie $skills_dir zlyhalo."
    print_success "Adresár pripravený: ${skills_dir}"

    # -------------------------------------------------------------------------
    # Download SKILL.md template
    # -------------------------------------------------------------------------
    printf "\n${BLUE}-- Sťahujem šablónu pre nový skill --${NC}\n"
    local template_dest="$skills_dir/SKILL-TEMPLATE.md"
    if [ -e "$template_dest" ]; then
        print_warning "SKILL-TEMPLATE.md už existuje — preskakujem."
    else
        fetch_file "$BASE_URL/SKILL.md" "$template_dest"
        print_success "Šablóna pre nový skill: .claude/skills/SKILL-TEMPLATE.md"
    fi

    # -------------------------------------------------------------------------
    # Download chosen skills
    # -------------------------------------------------------------------------
    printf "\n${BLUE}-- Sťahujem vybrané skills --${NC}\n"
    local installed=""
    for s in $selected; do
        local skill_dir="$skills_dir/$s"
        local skill_file="$skill_dir/SKILL.md"
        mkdir -p "$skill_dir" || print_error "Vytvorenie $skill_dir zlyhalo."
        if [ -e "$skill_file" ]; then
            print_warning ".claude/skills/$s/SKILL.md už existuje — preskakujem."
        else
            fetch_file "$BASE_URL/skills/$s/SKILL.md" "$skill_file"
            print_success "Skill nainštalovaný: .claude/skills/$s/SKILL.md"
        fi
        installed="${installed} $s"
    done
    installed="$(echo $installed)"  # trim

    # -------------------------------------------------------------------------
    # Update CLAUDE.md
    # -------------------------------------------------------------------------
    printf "\n${BLUE}-- Aktualizujem CLAUDE.md --${NC}\n"
    local claude_md="$project_path/CLAUDE.md"
    if [ -f "$claude_md" ]; then
        if grep -q "^## Skills" "$claude_md" 2>/dev/null; then
            print_warning "CLAUDE.md už obsahuje sekciu '## Skills' — neprepisujem."
        else
            {
                printf '\n## Skills\n'
                printf 'Pred prácou s týmito nástrojmi vždy prečítaj príslušný skill:\n'
                for s in $installed; do
                    printf -- '- %s: .claude/skills/%s/SKILL.md\n' "$s" "$s"
                done
            } >> "$claude_md" || print_error "Zápis do CLAUDE.md zlyhal."
            print_success "CLAUDE.md aktualizovaný — agent bude skills používať automaticky."
        fi
    else
        print_warning "CLAUDE.md nenájdený — preskakujem aktualizáciu."
        print_info "Pridaj do CLAUDE.md ručne sekciu '## Skills' so zoznamom súborov."
    fi

    # -------------------------------------------------------------------------
    # Final summary
    # -------------------------------------------------------------------------
    print_summary_box "$installed" "$project_path"

    print_info "Ďalší krok:"
    print_info "  1. Otvor .claude/skills/SKILL-TEMPLATE.md a pozri si štruktúru."
    print_info "  2. Pre vlastný skill skopíruj šablónu: cp .claude/skills/SKILL-TEMPLATE.md .claude/skills/MOJ-SKILL/SKILL.md"
    print_info "  3. Pridaj nový skill aj do CLAUDE.md sekcie '## Skills'."
}

main "$@"

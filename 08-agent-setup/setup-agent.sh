#!/usr/bin/env bash
# =============================================================================
# VCS Akadémia — Episode 08: Agent Setup — CLAUDE.md, PROJECT.md, TASKS.md...
# -----------------------------------------------------------------------------
# YouTube:    youtube.com/@VCSAkademia
# GitHub:     github.com/VirtuCyberSecurity/vcs-akademia
#
# Usage (Mac/Linux terminal or Windows Git Bash):
#   curl -O https://raw.githubusercontent.com/VirtuCyberSecurity/vcs-akademia/main/08-agent-setup/setup-agent.sh
#   bash setup-agent.sh
#
# Windows users: install Git Bash from https://gitforwindows.org
# (curl works the same as on Mac/Linux).
#
# This script runs LOCALLY on your computer. It:
#   1. Asks for project path, name, description and main stack.
#   2. Downloads agent onboarding templates from GitHub.
#   3. Fills in the basic info you provided.
#   4. Prints what you need to complete manually.
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
    for tool in curl awk mktemp; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing="${missing} ${tool}"
        fi
    done
    if [ -n "$missing" ]; then
        print_warning "Chýbajúce nástroje:${missing}"
        case "$OS" in
            windows) print_info "Na Windows potrebuješ Git Bash: https://gitforwindows.org" ;;
            mac)     print_info "Na Mac by mali byť štandardne dostupné (xcode-select --install)." ;;
            linux)   print_info "Na Debian/Ubuntu: sudo apt install curl gawk" ;;
        esac
        print_error "Doinštaluj chýbajúce nástroje a spusti skript znova."
    fi
}

# -----------------------------------------------------------------------------
# Literal in-place string replacement (no regex) — portable across Linux/Mac.
# Usage: replace_in_file FILE SEARCH REPLACE [mode]
#   mode: "all" (default) or "first"
# -----------------------------------------------------------------------------
replace_in_file() {
    local file="$1" search="$2" replace="$3" mode="${4:-all}"
    local tmpfile
    tmpfile=$(mktemp) || return 1

    awk -v s="$search" -v r="$replace" -v mode="$mode" '
        BEGIN { slen = length(s) }
        {
            line = $0
            out = ""
            while (mode != "done" && slen > 0 && (i = index(line, s)) > 0) {
                out = out substr(line, 1, i - 1) r
                line = substr(line, i + slen)
                if (mode == "first") { mode = "done"; break }
            }
            print out line
        }
    ' "$file" > "$tmpfile" && mv "$tmpfile" "$file"
}

# -----------------------------------------------------------------------------
# Download one template file from GitHub.
# Usage: fetch_template RELATIVE_PATH DEST_PATH
# -----------------------------------------------------------------------------
BASE_URL="https://raw.githubusercontent.com/VirtuCyberSecurity/vcs-akademia/main/08-agent-setup/templates"

fetch_template() {
    local rel="$1" dest="$2"
    local http_code
    http_code=$(curl -sS -w '%{http_code}' -o "$dest" "${BASE_URL}/${rel}" 2>/dev/null) || {
        print_error "Stiahnutie šablóny zlyhalo: ${rel} (curl chyba)"
    }
    if [ "$http_code" != "200" ]; then
        rm -f "$dest"
        print_error "Stiahnutie šablóny zlyhalo: ${rel} (HTTP ${http_code})"
    fi
    if [ ! -s "$dest" ]; then
        print_error "Šablóna ${rel} je prázdna."
    fi
}

# -----------------------------------------------------------------------------
# Final summary box
# -----------------------------------------------------------------------------
print_summary_box() {
    local name="$1" path="$2"
    echo
    printf "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}\n"
    printf "${GREEN}║${NC}   ${BLUE}VCS Akadémia — Epizóda 08${NC}                              ${GREEN}║${NC}\n"
    printf "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}\n"
    printf "${GREEN}║${NC} ${GREEN}Agent súbory vytvorené${NC}                                   ${GREEN}║${NC}\n"
    printf "${GREEN}║${NC} Projekt:     %-44s${GREEN}║${NC}\n" "$name"
    printf "${GREEN}║${NC} Umiestnenie: %-44s${GREEN}║${NC}\n" "$path"
    printf "${GREEN}║${NC}                                                          ${GREEN}║${NC}\n"
    printf "${GREEN}║${NC} Ďalší krok:                                              ${GREEN}║${NC}\n"
    printf "${GREEN}║${NC}  Doplň detaily v CLAUDE.md a PROJECT.md.                 ${GREEN}║${NC}\n"
    printf "${GREEN}║${NC}  Potom spusti: claude                                    ${GREEN}║${NC}\n"
    printf "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}\n"
    echo
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
TEMPLATE_FILES="CLAUDE.md PROJECT.md TASKS.md CHANGELOG.md"
PROMPT_FILES="new-feature.md fix-bug.md code-review.md deploy.md"

main() {
    printf "\n${BLUE}== VCS Akadémia — Epizóda 08: Nastavenie Claude Code Agenta ==${NC}\n\n"

    cat <<EOF
Tento skript pripraví tvoj projekt pre prácu s Claude Code agentom:
  1. Opýta sa na základné info o projekte.
  2. Stiahne šablóny (CLAUDE.md, PROJECT.md, TASKS.md, CHANGELOG.md + prompty).
  3. Vyplní základné info ktoré si zadal.
  4. Vypíše čo treba doplniť manuálne.
EOF
    echo
    confirm "Chceš pokračovať?"

    printf "\n${BLUE}-- Kontrola závislostí --${NC}\n"
    check_dependencies
    print_success "Všetky potrebné nástroje sú dostupné."

    # -------------------------------------------------------------------------
    # Collect project info
    # -------------------------------------------------------------------------
    printf "\n${BLUE}-- Údaje o projekte --${NC}\n"

    local project_path project_name project_desc project_stack

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
        print_warning "Adresár '$project_path' neexistuje."
        if ask_yn "Chceš ho vytvoriť?" "y"; then
            mkdir -p "$project_path" || print_error "Vytvorenie adresára zlyhalo."
            print_success "Adresár vytvorený: $project_path"
        else
            print_error "Zrušené — adresár neexistuje."
        fi
    fi

    # Normalize to absolute path where possible (best-effort)
    if command -v cd >/dev/null 2>&1; then
        local abs
        abs=$(cd "$project_path" 2>/dev/null && pwd) || abs="$project_path"
        project_path="$abs"
    fi

    project_name="$(ask "Názov projektu" "")"
    if [ -z "$project_name" ]; then
        print_error "Názov projektu nesmie byť prázdny."
    fi

    project_desc="$(ask "Krátky popis projektu (1-2 vety)" "")"
    if [ -z "$project_desc" ]; then
        print_error "Popis projektu nesmie byť prázdny."
    fi

    project_stack="$(ask "Hlavný jazyk / stack (napr. Go, Python, Node.js)" "")"
    if [ -z "$project_stack" ]; then
        project_stack="[doplň]"
    fi

    # -------------------------------------------------------------------------
    # Check existing files
    # -------------------------------------------------------------------------
    printf "\n${BLUE}-- Kontrola existujúcich súborov --${NC}\n"

    local skip_list="" present_count=0 total_count=0
    for f in $TEMPLATE_FILES; do
        total_count=$((total_count + 1))
        if [ -e "$project_path/$f" ]; then
            print_warning "$f už existuje — preskočím (nechcem prepísať)."
            skip_list="${skip_list} $f"
            present_count=$((present_count + 1))
        fi
    done

    if [ "$present_count" -eq "$total_count" ]; then
        print_warning "Všetky hlavné súbory už existujú."
        if ! ask_yn "Pokračovať? (stiahnu sa len chýbajúce prompty)" "n"; then
            print_info "Zrušené."
            exit 0
        fi
    fi

    echo
    printf "${BLUE}-- Zhrnutie --${NC}\n"
    print_info "Cesta:    ${project_path}"
    print_info "Projekt:  ${project_name}"
    print_info "Popis:    ${project_desc}"
    print_info "Stack:    ${project_stack}"
    echo
    confirm "Pokračovať?"

    # -------------------------------------------------------------------------
    # Download and fill in templates
    # -------------------------------------------------------------------------
    printf "\n${BLUE}-- Sťahujem a vypĺňam šablóny --${NC}\n"

    local today
    today=$(date +%Y-%m-%d)

    for f in $TEMPLATE_FILES; do
        local dest="$project_path/$f"
        if [ -e "$dest" ]; then
            continue
        fi
        print_info "Sťahujem $f..."
        fetch_template "$f" "$dest"
    done

    # Prompts directory
    local prompts_dir="$project_path/.claude/prompts"
    mkdir -p "$prompts_dir" || print_error "Vytvorenie $prompts_dir zlyhalo."

    for p in $PROMPT_FILES; do
        local dest="$prompts_dir/$p"
        if [ -e "$dest" ]; then
            print_warning ".claude/prompts/$p už existuje — preskakujem."
            continue
        fi
        print_info "Sťahujem .claude/prompts/$p..."
        fetch_template "prompts/$p" "$dest"
    done

    print_success "Všetky šablóny stiahnuté."

    # -------------------------------------------------------------------------
    # Fill in placeholders
    # -------------------------------------------------------------------------
    printf "\n${BLUE}-- Vypĺňam placeholders --${NC}\n"

    for f in $TEMPLATE_FILES; do
        local file="$project_path/$f"
        # Only touch files we just wrote (skip ones we left alone)
        case " $skip_list " in
            *" $f "*) continue ;;
        esac
        [ -f "$file" ] || continue

        # Project name — appears in PROJECT.md title
        replace_in_file "$file" "[Názov projektu]" "$project_name" "all"

        # Project description — two variants across templates
        replace_in_file "$file" "[Doplň: krátky popis projektu v 1-2 vetách]" "$project_desc" "all"
        replace_in_file "$file" "[Doplň: 1-2 vety čo projekt robí]" "$project_desc" "all"

        # Stack — fill only the FIRST occurrence of [doplň]
        replace_in_file "$file" "[doplň]" "$project_stack" "first"
    done

    # CHANGELOG date
    if [ -f "$project_path/CHANGELOG.md" ]; then
        case " $skip_list " in
            *" CHANGELOG.md "*) : ;;
            *) replace_in_file "$project_path/CHANGELOG.md" "[dátum]" "$today" "all" ;;
        esac
    fi

    print_success "Placeholders vyplnené."

    # -------------------------------------------------------------------------
    # Manual TODO hints
    # -------------------------------------------------------------------------
    printf "\n${BLUE}-- Čo treba doplniť manuálne --${NC}\n"
    print_info "Otvor tieto súbory a doplň detaily:"
    print_info "  ${project_path}/CLAUDE.md                         → čo nesmie agent robiť"
    print_info "  ${project_path}/PROJECT.md                        → štruktúra, ako deploynúť"
    print_info "  ${project_path}/TASKS.md                          → prvé úlohy projektu"
    print_info "  ${project_path}/.claude/prompts/deploy.md         → tvoj deploy postup"

    print_summary_box "$project_name" "$project_path"
}

main "$@"

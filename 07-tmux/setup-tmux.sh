#!/usr/bin/env bash
# =============================================================================
# VCS Akadémia — Episode 07: Tmux — session manager
# -----------------------------------------------------------------------------
# YouTube:    youtube.com/@VCSAkademia
# GitHub:     github.com/VirtuCyberSecurity/vcs-akademia
#
# Usage (Mac/Linux terminal or Windows Git Bash):
#   curl -O https://raw.githubusercontent.com/VirtuCyberSecurity/vcs-akademia/main/07-tmux/setup-tmux.sh
#   bash setup-tmux.sh
#
# Windows users: install Git Bash from https://gitforwindows.org
# (ssh works the same as on Mac/Linux).
#
# This script runs LOCALLY on your computer. It:
#   1. Asks for VPS details and a tmux session name.
#   2. Installs tmux on the VPS (apt-get) if missing.
#   3. Writes ~/.tmux.conf (history, mouse, colors); backs up any existing one.
#   4. Creates a named tmux session.
#   5. Optionally launches Claude Code inside the session.
#   6. Optionally opens an interactive SSH session and attaches you to tmux.
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

validate_session_name() {
    local name="$1"
    case "$name" in
        ''|*[!A-Za-z0-9_-]*) return 1 ;;
    esac
    return 0
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
# Build the remote script that installs tmux (if missing).
# Outputs one of: TMUX_ALREADY_OK <version> | TMUX_INSTALLED <version> | TMUX_FAILED <reason>
# -----------------------------------------------------------------------------
build_tmux_install_script() {
    cat <<'REMOTE_EOF'
set -e
export DEBIAN_FRONTEND=noninteractive

if command -v tmux >/dev/null 2>&1; then
    echo "TMUX_ALREADY_OK $(tmux -V)"
    exit 0
fi

apt-get update -qq >/dev/null 2>&1 || {
    echo "TMUX_FAILED apt_update"
    exit 1
}

apt-get install -y tmux >/dev/null 2>&1 || {
    echo "TMUX_FAILED apt_install"
    exit 1
}

if ! command -v tmux >/dev/null 2>&1; then
    echo "TMUX_FAILED not_found_after_install"
    exit 1
fi

echo "TMUX_INSTALLED $(tmux -V)"
REMOTE_EOF
}

# -----------------------------------------------------------------------------
# Build the remote script that writes ~/.tmux.conf for the SSH user.
# Backs up any existing config to ~/.tmux.conf.bak.
# Outputs: CONF_CREATED | CONF_REPLACED
# -----------------------------------------------------------------------------
build_tmux_conf_script() {
    cat <<'REMOTE_EOF'
set -e

CONF="$HOME/.tmux.conf"
STATE="CONF_CREATED"

if [ -f "$CONF" ]; then
    cp -f "$CONF" "$CONF.bak"
    STATE="CONF_REPLACED"
fi

cat > "$CONF" <<'TMUX_CONF_EOF'
# VCS Akadémia — tmux config
set -g history-limit 10000
set -g mouse on
set -g default-terminal "screen-256color"
set -g status-style bg=colour235,fg=colour136
set -g status-left "#[fg=colour166]#S "
set -g status-right "#[fg=colour166]%H:%M"
bind r source-file ~/.tmux.conf \; display "Config reloaded"
TMUX_CONF_EOF

echo "$STATE"
REMOTE_EOF
}

# -----------------------------------------------------------------------------
# Build the remote script that creates / recreates a named tmux session
# and optionally launches `claude` inside it.
#
# Args: SESSION_NAME RECREATE(yes|no) RUN_CLAUDE(yes|no)
#
# Outputs (last line):
#   SESSION_CREATED <name>
#   SESSION_EXISTS  <name>
#   SESSION_FAILED  <reason>
# Plus optional intermediate lines: CLAUDE_STARTED | CLAUDE_MISSING
# -----------------------------------------------------------------------------
build_session_script() {
    local session="$1" recreate="$2" run_claude="$3"
    cat <<REMOTE_EOF
set -e

SESSION="${session}"
RECREATE="${recreate}"
RUN_CLAUDE="${run_claude}"

if ! command -v tmux >/dev/null 2>&1; then
    echo "SESSION_FAILED tmux_missing"
    exit 1
fi

if tmux has-session -t "\$SESSION" 2>/dev/null; then
    if [ "\$RECREATE" = "yes" ]; then
        tmux kill-session -t "\$SESSION" || {
            echo "SESSION_FAILED kill"
            exit 1
        }
    else
        echo "SESSION_EXISTS \$SESSION"
        exit 0
    fi
fi

tmux new-session -d -s "\$SESSION" || {
    echo "SESSION_FAILED new_session"
    exit 1
}

if [ "\$RUN_CLAUDE" = "yes" ]; then
    if command -v claude >/dev/null 2>&1; then
        tmux send-keys -t "\$SESSION" "claude" Enter
        echo "CLAUDE_STARTED"
    else
        echo "CLAUDE_MISSING"
    fi
fi

echo "SESSION_CREATED \$SESSION"
REMOTE_EOF
}

# -----------------------------------------------------------------------------
# Step 1 — install tmux on the VPS
# -----------------------------------------------------------------------------
install_tmux_remote() {
    local user="$1" host="$2" port="$3" sudo_prefix="$4"

    print_info "Kontrolujem / inštalujem tmux..."
    local script output
    script="$(build_tmux_install_script)"

    if ! output=$(run_remote "$user" "$host" "$port" "$sudo_prefix" "$script"); then
        printf "%s\n" "$output" >&2
        print_error "Inštalácia tmux zlyhala."
    fi

    local last_line
    last_line=$(printf "%s" "$output" | tail -n1)
    case "$last_line" in
        TMUX_ALREADY_OK*)
            print_success "tmux už nainštalovaný (${last_line#TMUX_ALREADY_OK })."
            ;;
        TMUX_INSTALLED*)
            print_success "${last_line#TMUX_INSTALLED } nainštalovaný."
            ;;
        *)
            printf "%s\n" "$output" >&2
            print_error "Inštalácia tmux zlyhala (neočakávaný výstup)."
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Step 2 — write ~/.tmux.conf on the VPS (no sudo — user's HOME)
# -----------------------------------------------------------------------------
write_tmux_conf_remote() {
    local user="$1" host="$2" port="$3"

    print_info "Vytváram tmux konfiguráciu (~/.tmux.conf)..."
    local script output
    script="$(build_tmux_conf_script)"

    if ! output=$(run_remote "$user" "$host" "$port" "" "$script"); then
        printf "%s\n" "$output" >&2
        print_error "Vytvorenie ~/.tmux.conf zlyhalo."
    fi

    local last_line
    last_line=$(printf "%s" "$output" | tail -n1)
    case "$last_line" in
        CONF_CREATED)
            print_success "Tmux konfigurácia vytvorená."
            ;;
        CONF_REPLACED)
            print_success "Tmux konfigurácia vytvorená (pôvodná zálohovaná do ~/.tmux.conf.bak)."
            ;;
        *)
            printf "%s\n" "$output" >&2
            print_error "Vytvorenie ~/.tmux.conf zlyhalo (neočakávaný výstup)."
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Step 3 — create the tmux session (and optionally launch Claude inside it)
#
# Returns 0 if a session is ready (created OR kept existing), 1 on failure.
# Sets globals: SESSION_STATE (created|existed) and CLAUDE_STATE (started|missing|skipped|kept)
# -----------------------------------------------------------------------------
SESSION_STATE=""
CLAUDE_STATE="skipped"

create_session_remote() {
    local user="$1" host="$2" port="$3" session="$4" recreate="$5" run_claude="$6"

    print_info "Pripravujem tmux session '${session}'..."
    local script output
    script="$(build_session_script "$session" "$recreate" "$run_claude")"

    if ! output=$(run_remote "$user" "$host" "$port" "" "$script"); then
        printf "%s\n" "$output" >&2
        print_error "Vytvorenie session zlyhalo."
    fi

    if printf "%s\n" "$output" | grep -q '^CLAUDE_STARTED$'; then
        CLAUDE_STATE="started"
    elif printf "%s\n" "$output" | grep -q '^CLAUDE_MISSING$'; then
        CLAUDE_STATE="missing"
    fi

    local last_line
    last_line=$(printf "%s" "$output" | tail -n1)
    case "$last_line" in
        SESSION_CREATED*)
            SESSION_STATE="created"
            print_success "Session '${session}' vytvorená."
            ;;
        SESSION_EXISTS*)
            SESSION_STATE="existed"
            CLAUDE_STATE="kept"
            print_info "Session '${session}' ponechaná bez zmeny."
            ;;
        *)
            printf "%s\n" "$output" >&2
            print_error "Vytvorenie session zlyhalo (neočakávaný výstup)."
            ;;
    esac

    case "$CLAUDE_STATE" in
        started) print_success "Claude Code spustený v session '${session}'." ;;
        missing) print_warning "Claude Code nie je nainštalovaný na VPS — preskakujem (pozri epizódu 06)." ;;
    esac
}

# -----------------------------------------------------------------------------
# Final summary box
# -----------------------------------------------------------------------------
print_summary_box() {
    local user="$1" host="$2" port="$3" session="$4"

    echo
    printf "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}\n"
    printf "${GREEN}║${NC}   ${BLUE}VCS Akadémia — Epizóda 07${NC}                              ${GREEN}║${NC}\n"
    printf "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}\n"
    printf "${GREEN}║${NC} ${GREEN}Tmux pripravený na VPS${NC}                                   ${GREEN}║${NC}\n"
    printf "${GREEN}║${NC} Session:       %-42s${GREEN}║${NC}\n" "$session"
    printf "${GREEN}║${NC}                                                          ${GREEN}║${NC}\n"
    printf "${GREEN}║${NC} Pripojiť sa:                                             ${GREEN}║${NC}\n"
    printf "${GREEN}║${NC}   %-54s${GREEN}║${NC}\n" "ssh -p ${port} ${user}@${host}"
    printf "${GREEN}║${NC}   %-54s${GREEN}║${NC}\n" "tmux attach -t ${session}"
    printf "${GREEN}║${NC}                                                          ${GREEN}║${NC}\n"
    printf "${GREEN}║${NC} Odpojiť sa (session beží):  Ctrl+B  potom  D             ${GREEN}║${NC}\n"
    printf "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}\n"
    echo
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
main() {
    printf "\n${BLUE}== VCS Akadémia — Epizóda 07: Tmux — session manager ==${NC}\n\n"

    cat <<EOF
Tento skript pripraví tmux na tvojom VPS:
  1. Nainštaluje tmux (ak chýba).
  2. Vytvorí ~/.tmux.conf (história, mouse mode, lepšie farby).
  3. Vytvorí named session (default: claude).
  4. Voliteľne spustí Claude Code v session.
  5. Voliteľne ťa hneď pripojí k session cez SSH.
EOF
    echo

    print_warning "Tento skript inštaluje balík tmux na VPS a prepisuje ~/.tmux.conf (s zálohou)."
    echo
    confirm "Chceš pokračovať?"

    printf "\n${BLUE}-- Kontrola závislostí --${NC}\n"
    check_dependencies
    print_success "ssh je dostupné."

    printf "\n${BLUE}-- Údaje o VPS --${NC}\n"
    local vps_host vps_port vps_user session_name
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

    session_name="$(ask "Názov tmux session" "claude")"
    if ! validate_session_name "$session_name"; then
        print_error "Názov session smie obsahovať len písmená, čísla, '-' a '_'."
    fi

    local run_claude="no"
    if ask_yn "Spustiť Claude Code v session?" "y"; then
        run_claude="yes"
    fi

    local sudo_prefix=""
    if [ "$vps_user" != "root" ]; then
        sudo_prefix="sudo "
        print_warning "Pripájaš sa ako '$vps_user' — pre apt install sa použije sudo (možno si vyžiada heslo)."
    fi

    echo
    printf "${BLUE}-- Zhrnutie --${NC}\n"
    print_info "Cieľ:         ${vps_user}@${vps_host}:${vps_port}"
    print_info "Session:      ${session_name}"
    print_info "Claude Code:  $([ "$run_claude" = "yes" ] && echo "spustiť v session" || echo "nespúšťať")"
    echo
    confirm "Pokračovať?"

    printf "\n${BLUE}-- Krok 1/3 — Inštalácia tmux --${NC}\n"
    install_tmux_remote "$vps_user" "$vps_host" "$vps_port" "$sudo_prefix"

    printf "\n${BLUE}-- Krok 2/3 — Konfigurácia (~/.tmux.conf) --${NC}\n"
    write_tmux_conf_remote "$vps_user" "$vps_host" "$vps_port"

    printf "\n${BLUE}-- Krok 3/3 — Tmux session --${NC}\n"
    local recreate="no"
    # Probe whether the session already exists, so we can ask the user before recreating.
    local probe_out
    probe_out=$(ssh -p "$vps_port" \
                    -o StrictHostKeyChecking=accept-new \
                    -o ConnectTimeout=15 \
                    "${vps_user}@${vps_host}" \
                    "tmux has-session -t '${session_name}' 2>/dev/null && echo EXISTS || echo NONE" 2>/dev/null) || probe_out="NONE"
    probe_out=$(printf "%s" "$probe_out" | tail -n1)
    if [ "$probe_out" = "EXISTS" ]; then
        print_warning "Session '${session_name}' už existuje."
        if ask_yn "Chceš ju zabiť a vytvoriť novú?" "n"; then
            recreate="yes"
        fi
    fi

    create_session_remote "$vps_user" "$vps_host" "$vps_port" \
                          "$session_name" "$recreate" "$run_claude"

    print_summary_box "$vps_user" "$vps_host" "$vps_port" "$session_name"

    print_info "Užitočné príkazy:"
    print_info "  tmux ls                              # zoznam sessions"
    print_info "  tmux attach -t ${session_name}       # pripojiť sa"
    print_info "  tmux kill-session -t ${session_name} # zabiť session"
    echo

    if ask_yn "Chceš sa pripojiť k session '${session_name}' teraz?" "n"; then
        print_info "Pripájam ťa cez SSH... (odpoj sa cez Ctrl+B potom D)"
        echo
        ssh -t -p "$vps_port" \
            -o StrictHostKeyChecking=accept-new \
            "${vps_user}@${vps_host}" \
            "tmux attach -t '${session_name}'" || \
            print_warning "SSH session ukončené (alebo zlyhalo) — tmux session beží ďalej."
    else
        print_info "Hotovo. Pripojiť sa môžeš kedykoľvek:"
        print_info "  ssh -p ${vps_port} ${vps_user}@${vps_host}"
        print_info "  tmux attach -t ${session_name}"
    fi
}

main "$@"

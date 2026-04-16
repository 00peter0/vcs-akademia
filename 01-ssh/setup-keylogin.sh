#!/usr/bin/env bash
# =============================================================================
# VCS Akadémia — Episode 01: SSH Key Login
# -----------------------------------------------------------------------------
# YouTube:    VCS Akadémia
# GitHub:     https://github.com/VirtuCyberSecurity/vcs-akademia
# Source:     https://github.com/VirtuCyberSecurity/vcs-akademia/blob/main/01-ssh/setup-keylogin.sh
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/VirtuCyberSecurity/vcs-akademia/main/01-ssh/setup-keylogin.sh | bash
#
# Or download first, read it, then run:
#   curl -fsSL https://raw.githubusercontent.com/VirtuCyberSecurity/vcs-akademia/main/01-ssh/setup-keylogin.sh -o setup-keylogin.sh
#   less setup-keylogin.sh
#   bash setup-keylogin.sh
#
# What it does:
#   1. Generates an ed25519 SSH keypair if you don't have one yet.
#   2. Copies your public key to the VPS using ssh-copy-id.
#   3. Tests that key-based login works.
#   4. Disables password authentication on the VPS sshd_config.
#   5. Restarts sshd and re-tests the connection.
# =============================================================================

set -u
set -o pipefail

# -----------------------------------------------------------------------------
# Colors
# -----------------------------------------------------------------------------
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    C_RESET="$(tput sgr0)"
    C_RED="$(tput setaf 1)"
    C_GREEN="$(tput setaf 2)"
    C_YELLOW="$(tput setaf 3)"
    C_BLUE="$(tput setaf 4)"
    C_BOLD="$(tput bold)"
else
    C_RESET=""; C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_BOLD=""
fi

# -----------------------------------------------------------------------------
# Output helpers
# -----------------------------------------------------------------------------
print_info()    { printf "%s[INFO]%s %s\n"    "${C_BLUE}"   "${C_RESET}" "$*"; }
print_success() { printf "%s[OK]%s %s\n"      "${C_GREEN}"  "${C_RESET}" "$*"; }
print_warning() { printf "%s[WARN]%s %s\n"    "${C_YELLOW}" "${C_RESET}" "$*" >&2; }
print_error()   { printf "%s[ERROR]%s %s\n"   "${C_RED}"    "${C_RESET}" "$*" >&2; }
print_header()  { printf "\n%s== %s ==%s\n\n" "${C_BOLD}"   "$*" "${C_RESET}"; }

confirm() {
    local prompt="${1:-Continue?}"
    local reply
    printf "%s%s [y/N]: %s" "${C_YELLOW}" "${prompt}" "${C_RESET}"
    read -r reply </dev/tty
    case "${reply}" in
        y|Y|yes|YES) return 0 ;;
        *) print_info "Cancelled by user."; exit 0 ;;
    esac
}

ask() {
    # ask "Prompt text" "default_value" -> echoes user input or default
    local prompt="$1"
    local default="${2:-}"
    local reply
    if [ -n "${default}" ]; then
        printf "%s [%s]: " "${prompt}" "${default}" >&2
    else
        printf "%s: " "${prompt}" >&2
    fi
    read -r reply </dev/tty
    if [ -z "${reply}" ]; then
        echo "${default}"
    else
        echo "${reply}"
    fi
}

# -----------------------------------------------------------------------------
# Validate that required local tools exist
# -----------------------------------------------------------------------------
check_dependencies() {
    local missing=0
    for cmd in ssh ssh-keygen ssh-copy-id; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            print_error "Missing required command: ${cmd}"
            missing=1
        fi
    done
    if [ "${missing}" -ne 0 ]; then
        print_error "Install OpenSSH client tools and try again."
        print_info  "  macOS:  already included with the system."
        print_info  "  Linux:  apt install openssh-client   (Debian/Ubuntu)"
        print_info  "          dnf install openssh-clients  (Fedora/RHEL)"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Validate IP / hostname (very loose — we just refuse empty input)
# -----------------------------------------------------------------------------
validate_host() {
    local host="$1"
    if [ -z "${host}" ]; then
        print_error "VPS address cannot be empty."
        exit 1
    fi
}

validate_port() {
    local port="$1"
    case "${port}" in
        ''|*[!0-9]*) print_error "Port must be a number."; exit 1 ;;
    esac
    if [ "${port}" -lt 1 ] || [ "${port}" -gt 65535 ]; then
        print_error "Port must be between 1 and 65535."
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Generate SSH keypair if it doesn't exist
# -----------------------------------------------------------------------------
ensure_keypair() {
    local key_path="$1"
    if [ -f "${key_path}" ]; then
        print_info "Existing SSH key found at ${key_path} — reusing it."
        return 0
    fi

    print_info "No SSH key at ${key_path} — generating a new ed25519 keypair."
    mkdir -p "$(dirname "${key_path}")"
    chmod 700 "$(dirname "${key_path}")"

    if ! ssh-keygen -t ed25519 -f "${key_path}" -N "" -C "vcs-akademia-$(date +%Y%m%d)" >/dev/null; then
        print_error "ssh-keygen failed."
        exit 1
    fi
    print_success "Keypair generated."
}

# -----------------------------------------------------------------------------
# Copy public key to VPS
# -----------------------------------------------------------------------------
copy_pubkey() {
    local key_path="$1" user="$2" host="$3" port="$4"
    print_info "Copying public key to ${user}@${host}:${port}"
    print_warning "You will be asked for the VPS password — this is the LAST time."
    if ! ssh-copy-id -i "${key_path}.pub" -p "${port}" "${user}@${host}"; then
        print_error "ssh-copy-id failed."
        print_info  "Possible reasons:"
        print_info  "  - wrong IP, username or port"
        print_info  "  - wrong password"
        print_info  "  - VPS is unreachable (firewall, network)"
        print_info  "  - root login over password is disabled on the VPS"
        exit 1
    fi
    print_success "Public key copied."
}

# -----------------------------------------------------------------------------
# Test that key login works (no password prompt allowed)
# -----------------------------------------------------------------------------
test_key_login() {
    local key_path="$1" user="$2" host="$3" port="$4"
    print_info "Testing key-based login (no password prompt allowed)..."
    if ssh -i "${key_path}" -p "${port}" \
           -o BatchMode=yes \
           -o StrictHostKeyChecking=accept-new \
           -o ConnectTimeout=10 \
           "${user}@${host}" "echo '__VCS_KEYLOGIN_OK__'" 2>/dev/null | grep -q "__VCS_KEYLOGIN_OK__"; then
        print_success "Key-based login works."
        return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# Disable password auth in sshd_config and restart sshd (remote)
# -----------------------------------------------------------------------------
harden_sshd() {
    local key_path="$1" user="$2" host="$3" port="$4"

    print_info "Updating /etc/ssh/sshd_config on the VPS..."

    # The remote script:
    #   - backs up sshd_config to sshd_config.bak.<timestamp>
    #   - sets PasswordAuthentication no, PubkeyAuthentication yes
    #   - restarts sshd via systemctl OR service (whichever exists)
    local remote_script
    remote_script=$(cat <<'REMOTE_EOF'
set -e

SSHD_CONF="/etc/ssh/sshd_config"
TS="$(date +%Y%m%d-%H%M%S)"
BACKUP="${SSHD_CONF}.bak.${TS}"

if [ ! -f "${SSHD_CONF}" ]; then
    echo "ERROR: ${SSHD_CONF} not found." >&2
    exit 1
fi

cp "${SSHD_CONF}" "${BACKUP}"
echo "Backup saved to ${BACKUP}"

set_option() {
    local key="$1" value="$2"
    if grep -qE "^[[:space:]]*#?[[:space:]]*${key}[[:space:]]+" "${SSHD_CONF}"; then
        sed -i.tmp -E "s|^[[:space:]]*#?[[:space:]]*${key}[[:space:]]+.*|${key} ${value}|" "${SSHD_CONF}"
        rm -f "${SSHD_CONF}.tmp"
    else
        printf "\n%s %s\n" "${key}" "${value}" >> "${SSHD_CONF}"
    fi
}

set_option PasswordAuthentication no
set_option PubkeyAuthentication  yes
set_option ChallengeResponseAuthentication no

# Validate config before restart
if command -v sshd >/dev/null 2>&1; then
    if ! sshd -t 2>/tmp/sshd_test_err; then
        echo "ERROR: sshd config test failed:" >&2
        cat /tmp/sshd_test_err >&2
        echo "Restoring backup..." >&2
        cp "${BACKUP}" "${SSHD_CONF}"
        exit 1
    fi
fi

# Restart sshd — try systemctl first, then service
if command -v systemctl >/dev/null 2>&1; then
    if systemctl list-unit-files | grep -qE '^(ssh|sshd)\.service'; then
        if systemctl list-unit-files | grep -qE '^ssh\.service'; then
            systemctl restart ssh
        else
            systemctl restart sshd
        fi
    else
        service ssh restart 2>/dev/null || service sshd restart
    fi
elif command -v service >/dev/null 2>&1; then
    service ssh restart 2>/dev/null || service sshd restart
else
    echo "ERROR: cannot find systemctl or service to restart sshd." >&2
    exit 1
fi

echo "sshd restarted."
REMOTE_EOF
)

    # Run remote script as root via sudo if user is not root
    local sudo_prefix=""
    if [ "${user}" != "root" ]; then
        sudo_prefix="sudo "
        print_warning "User '${user}' is not root — sudo will be used on the VPS."
        print_warning "You may be asked for the sudo password."
    fi

    if ! ssh -i "${key_path}" -p "${port}" -t \
             -o StrictHostKeyChecking=accept-new \
             "${user}@${host}" "${sudo_prefix}bash -s" <<<"${remote_script}"; then
        print_error "Failed to update sshd_config on the VPS."
        print_warning "The VPS sshd_config may or may not have been changed — check manually."
        exit 1
    fi

    print_success "sshd_config updated and sshd restarted."
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
main() {
    print_header "VCS Akadémia — Episode 01: SSH Key Login"
    cat <<EOF
This script will:
  1. Generate an ed25519 SSH keypair (if you don't have one).
  2. Copy your public key to the VPS.
  3. Test key-based login.
  4. Disable password authentication on the VPS.
  5. Restart sshd and verify the new config.

After this script finishes, password login on the VPS will be DISABLED.
You will only be able to log in using your private key (~/.ssh/id_ed25519).

EOF

    confirm "Do you want to continue?"

    print_header "Step 1 — Checking local dependencies"
    check_dependencies
    print_success "ssh, ssh-keygen and ssh-copy-id are available."

    print_header "Step 2 — VPS connection details"
    local vps_host vps_user vps_port
    vps_host="$(ask "VPS IP address or hostname" "")"
    validate_host "${vps_host}"
    vps_user="$(ask "Username on the VPS" "root")"
    vps_port="$(ask "SSH port" "22")"
    validate_port "${vps_port}"

    local key_path="${HOME}/.ssh/id_ed25519"

    echo
    print_info "Summary of what will happen:"
    print_info "  Target:   ${vps_user}@${vps_host}:${vps_port}"
    print_info "  Key path: ${key_path}"
    echo
    confirm "Proceed?"

    print_header "Step 3 — Generating SSH keypair (if needed)"
    ensure_keypair "${key_path}"

    print_header "Step 4 — Copying public key to the VPS"
    copy_pubkey "${key_path}" "${vps_user}" "${vps_host}" "${vps_port}"

    print_header "Step 5 — Testing key-based login"
    if ! test_key_login "${key_path}" "${vps_user}" "${vps_host}" "${vps_port}"; then
        print_error "Key-based login does NOT work yet."
        print_warning "We will NOT modify sshd_config until key login is verified."
        print_info    "Try connecting manually to debug:"
        print_info    "  ssh -v -i ${key_path} -p ${vps_port} ${vps_user}@${vps_host}"
        exit 1
    fi

    print_header "Step 6 — Disabling password authentication on the VPS"
    print_warning "About to modify /etc/ssh/sshd_config and restart sshd."
    print_warning "If something goes wrong, password login will still work UNTIL sshd restarts."
    confirm "Disable password authentication and restart sshd?"
    harden_sshd "${key_path}" "${vps_user}" "${vps_host}" "${vps_port}"

    print_header "Step 7 — Verifying key login after sshd restart"
    sleep 2
    if ! test_key_login "${key_path}" "${vps_user}" "${vps_host}" "${vps_port}"; then
        print_error "Key login FAILED after sshd restart!"
        print_warning "Do NOT close your existing SSH sessions to the VPS."
        print_warning "The script did NOT roll back automatically — that is intentional."
        print_info    "On the VPS, restore the backup manually:"
        print_info    "  ls /etc/ssh/sshd_config.bak.*"
        print_info    "  cp /etc/ssh/sshd_config.bak.<timestamp> /etc/ssh/sshd_config"
        print_info    "  systemctl restart ssh   # or: service ssh restart"
        exit 1
    fi
    print_success "Key login verified after sshd restart."

    print_header "Done — Summary"
    print_success "SSH key login is set up and password login is disabled."
    echo
    printf "  %sVPS:%s         %s\n" "${C_BOLD}" "${C_RESET}" "${vps_host}"
    printf "  %sUser:%s        %s\n" "${C_BOLD}" "${C_RESET}" "${vps_user}"
    printf "  %sPort:%s        %s\n" "${C_BOLD}" "${C_RESET}" "${vps_port}"
    printf "  %sPrivate key:%s %s\n" "${C_BOLD}" "${C_RESET}" "${key_path}"
    printf "  %sPublic key:%s  %s\n" "${C_BOLD}" "${C_RESET}" "${key_path}.pub"
    echo
    print_info "Connect from now on with:"
    printf "    %sssh -i %s -p %s %s@%s%s\n\n" \
        "${C_GREEN}" "${key_path}" "${vps_port}" "${vps_user}" "${vps_host}" "${C_RESET}"
    print_warning "Back up your private key (${key_path}) — if you lose it, you lose access."
}

on_exit() {
    local exit_code=$?
    if [ "${exit_code}" -ne 0 ]; then
        echo
        print_error "Script ended with errors (exit code ${exit_code})."
    fi
}
trap on_exit EXIT

main "$@"

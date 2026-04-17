#!/usr/bin/env bash
# =============================================================================
# VCS Akadémia — Episode 05: Nginx + SSL
# -----------------------------------------------------------------------------
# YouTube:    youtube.com/@VCSAkademia
# GitHub:     github.com/VirtuCyberSecurity/vcs-akademia
#
# Usage (Mac/Linux terminal or Windows Git Bash):
#   curl -O https://raw.githubusercontent.com/00peter0/vcs-akademia/main/05-nginx-ssl/setup-nginx-ssl.sh
#   bash setup-nginx-ssl.sh
#
# Windows users: install Git Bash from https://gitforwindows.org
# (ssh and curl work the same as on Mac/Linux).
#
# This script runs LOCALLY on your computer. It:
#   1. Asks for VPS details, domain and Let's Encrypt email.
#   2. Verifies that the domain's A record points to the VPS IP.
#   3. Installs Nginx + Certbot on the VPS.
#   4. Creates an Nginx server block for the domain.
#   5. Obtains a Let's Encrypt SSL certificate and enables HTTP -> HTTPS.
#   6. Enables automatic certificate renewal.
#   7. Tests that HTTPS is reachable.
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
    local missing=0
    for tool in ssh curl; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            print_warning "Chýba nástroj: $tool"
            missing=1
        fi
    done
    if [ "$missing" -ne 0 ]; then
        case "$OS" in
            windows) print_info "Na Windows potrebuješ Git Bash: https://gitforwindows.org" ;;
            mac)     print_info "Na Mac skús: brew install openssh curl" ;;
            linux)   print_info "Na Debian/Ubuntu: sudo apt install openssh-client curl" ;;
        esac
        print_error "Doinštaluj chýbajúce nástroje a spusti skript znova."
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

validate_domain() {
    local d="$1"
    case "$d" in
        http://*|https://*) return 1 ;;
        */*)                return 1 ;;
        *.*)                ;;
        *)                  return 1 ;;
    esac
    case "$d" in
        *[!a-zA-Z0-9.-]*) return 1 ;;
    esac
    return 0
}

validate_email() {
    local e="$1"
    case "$e" in
        ?*@?*.?*) return 0 ;;
        *)        return 1 ;;
    esac
}

# -----------------------------------------------------------------------------
# Resolve domain to IP locally (try dig, then nslookup, then host)
# -----------------------------------------------------------------------------
resolve_domain_ip() {
    local domain="$1"
    local ip=""

    if command -v dig >/dev/null 2>&1; then
        ip="$(dig +short A "$domain" 2>/dev/null | grep -E '^[0-9.]+$' | head -n1)"
    fi
    if [ -z "$ip" ] && command -v host >/dev/null 2>&1; then
        ip="$(host -t A "$domain" 2>/dev/null | awk '/has address/ {print $4; exit}')"
    fi
    if [ -z "$ip" ] && command -v nslookup >/dev/null 2>&1; then
        ip="$(nslookup -type=A "$domain" 2>/dev/null \
              | awk '/^Address: / {print $2}' | grep -E '^[0-9.]+$' | head -n1)"
    fi
    echo "$ip"
}

# -----------------------------------------------------------------------------
# Get the VPS public IP via SSH
# -----------------------------------------------------------------------------
get_vps_public_ip() {
    local user="$1" host="$2" port="$3"
    ssh -p "$port" \
        -o StrictHostKeyChecking=accept-new \
        -o ConnectTimeout=10 \
        "${user}@${host}" \
        "curl -s --max-time 5 https://ifconfig.me || curl -s --max-time 5 https://api.ipify.org" \
        2>/dev/null
}

# -----------------------------------------------------------------------------
# Build the remote script that installs Nginx + Certbot and creates a server block.
# Runs with root privileges on the VPS (see sudo_prefix below).
# -----------------------------------------------------------------------------
build_install_script() {
    local domain="$1"

    cat <<REMOTE_EOF
set -e

export DEBIAN_FRONTEND=noninteractive

NEED_INSTALL=0
if ! command -v nginx >/dev/null 2>&1; then NEED_INSTALL=1; fi
if ! command -v certbot >/dev/null 2>&1; then NEED_INSTALL=1; fi

if [ "\$NEED_INSTALL" -eq 1 ]; then
    echo "INSTALLING_PACKAGES"
    apt-get update -qq
    apt-get install -y nginx certbot python3-certbot-nginx
fi

mkdir -p /var/www/${domain}
if [ ! -f /var/www/${domain}/index.html ]; then
    cat > /var/www/${domain}/index.html <<'HTML'
<!DOCTYPE html>
<html lang="sk">
<head>
    <meta charset="UTF-8">
    <title>VCS Akadémia — ${domain}</title>
</head>
<body>
    <h1>VCS Akadémia — ${domain} funguje</h1>
    <p>Nginx a SSL certifikát sú nainštalované. Tento súbor nahraď vlastným obsahom v /var/www/${domain}/.</p>
</body>
</html>
HTML
fi
chown -R www-data:www-data /var/www/${domain}

mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled

cat > /etc/nginx/sites-available/${domain} <<'CONF'
server {
    listen 80;
    listen [::]:80;
    server_name ${domain} www.${domain};

    root /var/www/${domain};
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
CONF

ln -sf /etc/nginx/sites-available/${domain} /etc/nginx/sites-enabled/${domain}
rm -f /etc/nginx/sites-enabled/default

if ! nginx -t 2>&1; then
    echo "NGINX_CONFIG_BAD"
    exit 1
fi

systemctl enable nginx >/dev/null 2>&1 || true
systemctl reload nginx 2>/dev/null || systemctl restart nginx

echo "NGINX_READY"
REMOTE_EOF
}

# -----------------------------------------------------------------------------
# Build the remote script that runs Certbot
# -----------------------------------------------------------------------------
build_certbot_script() {
    local domain="$1" email="$2"

    cat <<REMOTE_EOF
set -e

certbot --nginx \
    -d ${domain} -d www.${domain} \
    --non-interactive --agree-tos \
    --email ${email} \
    --redirect

if systemctl list-unit-files 2>/dev/null | grep -q '^certbot.timer'; then
    systemctl enable certbot.timer >/dev/null 2>&1 || true
    systemctl start certbot.timer  >/dev/null 2>&1 || true
    echo "RENEW_TIMER_OK"
else
    echo "0 3 * * * root certbot renew --quiet" > /etc/cron.d/certbot-renew
    chmod 644 /etc/cron.d/certbot-renew
    echo "RENEW_CRON_OK"
fi

echo "CERTBOT_DONE"
REMOTE_EOF
}

# -----------------------------------------------------------------------------
# Run the install/server-block remote script
# -----------------------------------------------------------------------------
install_nginx_remote() {
    local user="$1" host="$2" port="$3" domain="$4" sudo_prefix="$5"

    local script output
    script="$(build_install_script "$domain")"

    print_info "Inštalujem Nginx + Certbot a vytváram server block pre ${domain}..."
    if ! output=$(ssh -p "$port" \
             -o StrictHostKeyChecking=accept-new \
             "${user}@${host}" "${sudo_prefix}bash -s" <<<"$script" 2>&1); then
        printf "%s\n" "$output" >&2
        if printf "%s" "$output" | grep -q "NGINX_CONFIG_BAD"; then
            print_error "Nginx konfigurácia má chybu — pozri výstup vyššie."
        fi
        print_error "Inštalácia/konfigurácia Nginx zlyhala."
    fi

    if printf "%s" "$output" | grep -q "INSTALLING_PACKAGES"; then
        print_success "Nginx + Certbot nainštalované."
    else
        print_info "Nginx + Certbot už boli nainštalované — preskakujem inštaláciu."
    fi

    if ! printf "%s" "$output" | grep -q "NGINX_READY"; then
        printf "%s\n" "$output" >&2
        print_error "Nginx sa nepodarilo pripraviť."
    fi
    print_success "Server block vytvorený a Nginx test OK."
}

# -----------------------------------------------------------------------------
# Run Certbot remotely
# -----------------------------------------------------------------------------
run_certbot_remote() {
    local user="$1" host="$2" port="$3" domain="$4" email="$5" sudo_prefix="$6"

    local script output
    script="$(build_certbot_script "$domain" "$email")"

    print_info "Žiadam SSL certifikát od Let's Encrypt pre ${domain}..."
    if ! output=$(ssh -p "$port" \
             -o StrictHostKeyChecking=accept-new \
             "${user}@${host}" "${sudo_prefix}bash -s" <<<"$script" 2>&1); then
        printf "%s\n" "$output" >&2
        echo
        print_warning "Certbot zlyhal. Možné príčiny:"
        print_warning "  - Doména nesmeruje na tento VPS (skontroluj A record u registrátora)"
        print_warning "  - Port 80 nie je otvorený (skontroluj UFW — epizóda 03)"
        print_warning "  - Let's Encrypt rate limit (max 5 certifikátov za týždeň pre doménu)"
        print_error "Získanie SSL certifikátu zlyhalo."
    fi

    print_success "SSL certifikát získaný a HTTPS redirect aktivovaný."

    if printf "%s" "$output" | grep -q "RENEW_TIMER_OK"; then
        print_success "Automatické obnovovanie nastavené cez certbot.timer."
    elif printf "%s" "$output" | grep -q "RENEW_CRON_OK"; then
        print_success "Automatické obnovovanie nastavené cez cron (/etc/cron.d/certbot-renew)."
    else
        print_warning "Nepodarilo sa overiť automatické obnovovanie — skontroluj manuálne."
    fi
}

# -----------------------------------------------------------------------------
# Local HTTPS reachability test
# -----------------------------------------------------------------------------
test_https_local() {
    local domain="$1"
    local code
    code="$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 "https://${domain}" 2>/dev/null || echo "000")"
    case "$code" in
        200|301|302|308)
            print_success "HTTPS funguje (HTTP $code) — https://${domain}"
            return 0
            ;;
        *)
            print_warning "HTTPS test zlyhal (HTTP $code). Skontroluj manuálne: https://${domain}"
            return 1
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Final summary box
# -----------------------------------------------------------------------------
print_summary_box() {
    local domain="$1"
    echo
    printf "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}\n"
    printf "${GREEN}║${NC}   ${BLUE}VCS Akadémia — Epizóda 05${NC}     ${GREEN}║${NC}\n"
    printf "${GREEN}╠══════════════════════════════════════════════════════════╣${NC}\n"
    printf "${GREEN}║${NC} ${GREEN}Nginx + SSL je aktívny${NC}         ${GREEN}║${NC}\n"
    printf "${GREEN}║${NC} Web:           %-42s                        ${GREEN}║${NC}\n" "https://${domain}"
    printf "${GREEN}║${NC} Certifikát:    %-42s                        ${GREEN}║${NC}\n" "Let's Encrypt (90 dní)"
    printf "${GREEN}║${NC} Obnovovanie:   %-42s                        ${GREEN}║${NC}\n" "automatické"
    printf "${GREEN}║${NC}                                             ${GREEN}║${NC}\n"
    printf "${GREEN}║${NC} Web root:      %-42s                        ${GREEN}║${NC}\n" "/var/www/${domain}"
    printf "${GREEN}║${NC} Nginx config:  %-42s                        ${GREEN}║${NC}\n" "/etc/nginx/sites-available/${domain}"
    printf "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}\n"
    echo
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------
main() {
    printf "\n${BLUE}== VCS Akadémia — Epizóda 05: Nginx + SSL ==${NC}\n\n"

    cat <<EOF
Tento skript nainštaluje Nginx a získa SSL certifikát od Let's Encrypt:
  1. Overí, že tvoja doména smeruje na IP VPS.
  2. Nainštaluje Nginx + Certbot na VPS.
  3. Vytvorí server block + placeholder web stránku.
  4. Získa bezplatný SSL certifikát (platný 90 dní).
  5. Zapne HTTP -> HTTPS presmerovanie.
  6. Nastaví automatické obnovovanie certifikátu.
EOF
    echo

    print_warning "Tento skript inštaluje balíky a mení Nginx konfiguráciu na VPS."
    echo
    confirm "Chceš pokračovať?"

    printf "\n${BLUE}-- Kontrola závislostí --${NC}\n"
    check_dependencies
    print_success "ssh a curl sú dostupné."

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

    printf "\n${BLUE}-- Doména a Let's Encrypt --${NC}\n"
    local domain email
    domain="$(ask "Doména (napr. moja-domena.sk — bez https://)" "")"
    if [ -z "$domain" ] || ! validate_domain "$domain"; then
        print_error "Doména musí byť platná (napr. example.sk), bez https:// a bez lomky."
    fi

    email="$(ask "Email pre Let's Encrypt (notifikácie o expirácii)" "")"
    if [ -z "$email" ] || ! validate_email "$email"; then
        print_error "Email musí byť v tvare meno@domena.sk."
    fi

    local sudo_prefix=""
    if [ "$vps_user" != "root" ]; then
        sudo_prefix="sudo "
        print_warning "Pripájaš sa ako '$vps_user' — na VPS sa použije sudo (možno si vyžiada heslo)."
    fi

    echo
    printf "${BLUE}-- Zhrnutie --${NC}\n"
    print_info "Cieľ:    ${vps_user}@${vps_host}:${vps_port}"
    print_info "Doména:  ${domain}"
    print_info "Email:   ${email}"
    echo
    confirm "Pokračovať?"

    printf "\n${BLUE}-- Krok 1/5 — Overenie že doména smeruje na VPS --${NC}\n"
    print_info "Zisťujem verejnú IP VPS..."
    local vps_public_ip
    vps_public_ip="$(get_vps_public_ip "$vps_user" "$vps_host" "$vps_port")"
    if [ -z "$vps_public_ip" ]; then
        print_warning "Nepodarilo sa zistiť verejnú IP VPS cez ifconfig.me."
        vps_public_ip="$vps_host"
        print_info "Použijem zadanú IP/host: $vps_public_ip"
    else
        print_info "Verejná IP VPS: $vps_public_ip"
    fi

    print_info "Rozlišujem DNS záznam pre ${domain}..."
    local domain_ip
    domain_ip="$(resolve_domain_ip "$domain")"
    if [ -z "$domain_ip" ]; then
        print_warning "Nepodarilo sa rozlíšiť doménu ${domain} (žiadny lokálny DNS nástroj)."
        print_warning "Skript bude pokračovať, ale Let's Encrypt zlyhá ak doména nesmeruje na VPS."
        confirm "Chceš pokračovať aj tak?"
    else
        print_info "DNS záznam ${domain} -> ${domain_ip}"
        if [ "$domain_ip" = "$vps_public_ip" ]; then
            print_success "Doména smeruje správne na VPS."
        else
            print_warning "Doména ${domain} nesmeruje na IP VPS ${vps_public_ip}."
            print_warning "Aktuálna IP domény: ${domain_ip}"
            print_warning "Let's Encrypt certifikát nebude fungovať, pokým sa to nezhoduje."
            confirm "Chceš pokračovať aj tak? (napr. DNS sa ešte propaguje)"
        fi
    fi

    printf "\n${BLUE}-- Krok 2/5 — Inštalácia Nginx + Certbot --${NC}\n"
    install_nginx_remote "$vps_user" "$vps_host" "$vps_port" "$domain" "$sudo_prefix"

    printf "\n${BLUE}-- Krok 3/5 — Získanie SSL certifikátu --${NC}\n"
    run_certbot_remote "$vps_user" "$vps_host" "$vps_port" "$domain" "$email" "$sudo_prefix"

    printf "\n${BLUE}-- Krok 4/5 — Test HTTPS --${NC}\n"
    sleep 2
    test_https_local "$domain" || true

    printf "\n${BLUE}-- Krok 5/5 — Hotovo --${NC}\n"
    print_summary_box "$domain"
    print_info "Pridať novú aplikáciu/doménu:"
    print_info "  1. vytvor nový server block v /etc/nginx/sites-available/"
    print_info "  2. ln -sf ... /etc/nginx/sites-enabled/"
    print_info "  3. sudo certbot --nginx -d nova-domena.sk"
}

main "$@"

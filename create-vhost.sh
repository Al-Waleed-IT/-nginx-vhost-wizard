#!/usr/bin/env bash
#
#  ███████╗███╗   ██╗██╗   ██╗ █████╗ ██╗   ██╗███████╗ ██████╗ ███████╗████████╗
#  ██╔════╝████╗  ██║██║   ██║██╔══██╗╚██╗ ██╔╝██╔════╝██╔═══██╗██╔════╝╚══██╔══╝
#  █████╗  ██╔██╗ ██║██║   ██║███████║ ╚████╔╝ ███████╗██║   ██║█████╗     ██║
#  ██╔══╝  ██║╚██╗██║╚██╗ ██╔╝██╔══██║  ╚██╔╝  ╚════██║██║   ██║██╔══╝     ██║
#  ███████╗██║ ╚████║ ╚████╔╝ ██║  ██║   ██║   ███████║╚██████╔╝██║        ██║
#  ╚══════╝╚═╝  ╚═══╝  ╚═══╝  ╚═╝  ╚═╝   ╚═╝   ╚══════╝ ╚═════╝ ╚═╝        ╚═╝
#
#  Nginx vhost + PHP-FPM + SSL (signed by Envaysoft Root CA) generator
#  An interactive, colourful TUI.  Run with sudo (or it will re-exec itself).
#
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
#  Configuration / paths
# ─────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
CA_DIR="/etc/ssl/envaysoft"
CA_CRT="$CA_DIR/envaysoft-ca.crt"
CA_KEY="$CA_DIR/envaysoft-ca.key"
CA_SRL="$CA_DIR/envaysoft-ca.srl"
NGINX_AVAILABLE="/etc/nginx/sites-available"
NGINX_ENABLED="/etc/nginx/sites-enabled"
WWW_ROOT="/var/www"
HOSTS_FILE="/etc/hosts"
CERT_DAYS=825

# ─────────────────────────────────────────────────────────────────────────────
#  Colours & styling
# ─────────────────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  ESC=$'\033'
  RESET="${ESC}[0m";   BOLD="${ESC}[1m";    DIM="${ESC}[2m";    ITAL="${ESC}[3m"
  RED="${ESC}[38;5;203m";    GREEN="${ESC}[38;5;84m";   YELLOW="${ESC}[38;5;221m"
  BLUE="${ESC}[38;5;75m";    MAGENTA="${ESC}[38;5;213m"; CYAN="${ESC}[38;5;87m"
  ORANGE="${ESC}[38;5;215m"; PURPLE="${ESC}[38;5;141m"; PINK="${ESC}[38;5;211m"
  GREY="${ESC}[38;5;245m";   WHITE="${ESC}[38;5;255m"
  BG_BLUE="${ESC}[48;5;24m"; BG_DARK="${ESC}[48;5;236m"
else
  ESC=""; RESET=""; BOLD=""; DIM=""; ITAL=""
  RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""; CYAN=""
  ORANGE=""; PURPLE=""; PINK=""; GREY=""; WHITE=""; BG_BLUE=""; BG_DARK=""
fi

CHECK="${GREEN}✔${RESET}"; CROSS="${RED}✘${RESET}"; ARROW="${CYAN}➜${RESET}"
STAR="${YELLOW}★${RESET}";  GEAR="${PURPLE}⚙${RESET}"; LOCK="${ORANGE}🔒${RESET}"

# ─────────────────────────────────────────────────────────────────────────────
#  Helpers
# ─────────────────────────────────────────────────────────────────────────────
say()    { printf '%b\n' "$*"; }
info()   { printf '  %b %b\n' "$ARROW" "$*"; }
ok()     { printf '  %b %b\n' "$CHECK" "$*"; }
warn()   { printf '  %b %b\n' "${YELLOW}!${RESET}" "${YELLOW}$*${RESET}"; }
err()    { printf '  %b %b\n' "$CROSS" "${RED}$*${RESET}" >&2; }
die()    { err "$*"; echo; exit 1; }

hr() {
  local w; w=$(tput cols 2>/dev/null || echo 78); (( w > 80 )) && w=80
  printf "${GREY}"; printf '─%.0s' $(seq 1 "$w"); printf "${RESET}\n"
}

# Centred banner
banner() {
  clear 2>/dev/null || true
  say ""
  say "${MAGENTA}${BOLD}    ╔═══════════════════════════════════════════════════════════════╗${RESET}"
  say "${MAGENTA}${BOLD}    ║${RESET}   ${CYAN}${BOLD}🌐  E N V A Y S O F T   ·   N G I N X   V H O S T${RESET}   ${MAGENTA}${BOLD}║${RESET}"
  say "${MAGENTA}${BOLD}    ║${RESET}        ${GREY}PHP-FPM  +  SSL signed by Envaysoft Root CA${RESET}        ${MAGENTA}${BOLD}║${RESET}"
  say "${MAGENTA}${BOLD}    ╚═══════════════════════════════════════════════════════════════╝${RESET}"
  say ""
}

# Section header
section() {
  echo
  say "${BG_BLUE}${WHITE}${BOLD}  $1  ${RESET}"
  echo
}

# A tiny spinner that runs a command, showing a live status line.
#   spin "Message" command args...
spin() {
  local msg="$1"; shift
  local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local tmp; tmp="$(mktemp)"
  ( "$@" ) >"$tmp" 2>&1 &
  local pid=$! i=0
  if [[ -t 1 ]]; then
    while kill -0 "$pid" 2>/dev/null; do
      printf "\r  ${PURPLE}%s${RESET} %b " "${frames[i++ % ${#frames[@]}]}" "$msg"
      sleep 0.08
    done
  fi
  if wait "$pid"; then
    printf "\r  %b %b\033[K\n" "$CHECK" "$msg"
    rm -f "$tmp"; return 0
  else
    printf "\r  %b %b\033[K\n" "$CROSS" "$msg"
    say "${DIM}$(sed 's/^/      /' "$tmp")${RESET}"
    rm -f "$tmp"; return 1
  fi
}

# Prompt with default.  Usage: ask VAR "Question" "default"
ask() {
  local __var="$1" __q="$2" __def="${3:-}" __ans
  if [[ -n "$__def" ]]; then
    printf "  %b %b ${GREY}[%s]${RESET} " "$ARROW" "${WHITE}$__q${RESET}" "$__def"
  else
    printf "  %b %b " "$ARROW" "${WHITE}$__q${RESET}"
  fi
  read -r __ans </dev/tty || true
  [[ -z "$__ans" ]] && __ans="$__def"
  printf -v "$__var" '%s' "$__ans"
}

# Yes/No prompt.  Usage: confirm "Question" "Y|N"  -> returns 0 for yes
confirm() {
  local q="$1" def="${2:-Y}" ans hint
  if [[ "$def" =~ ^[Yy] ]]; then hint="${GREEN}Y${RESET}/${GREY}n${RESET}"; else hint="${GREY}y${RESET}/${RED}N${RESET}"; fi
  while true; do
    printf "  %b %b ${GREY}(${RESET}%b${GREY})${RESET} " "$STAR" "${WHITE}$q${RESET}" "$hint"
    read -r ans </dev/tty || true
    ans="${ans:-$def}"
    case "$ans" in
      [Yy]*) return 0 ;;
      [Nn]*) return 1 ;;
      *) warn "Please answer y or n." ;;
    esac
  done
}

# Pretty key/value summary line
kv() { printf "    ${GREY}%-16s${RESET} %b\n" "$1" "$2"; }

# ─────────────────────────────────────────────────────────────────────────────
#  Privilege check — re-exec with sudo if needed
# ─────────────────────────────────────────────────────────────────────────────
ensure_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    warn "Root privileges are required — re-running with sudo…"
    exec sudo -E bash "$0" "$@"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  Dependency check
# ─────────────────────────────────────────────────────────────────────────────
check_deps() {
  local missing=()
  for bin in nginx openssl; do
    command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
  done
  if (( ${#missing[@]} )); then
    die "Missing required commands: ${missing[*]}"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  Ensure the Envaysoft Root CA exists; copy from script dir if absent
# ─────────────────────────────────────────────────────────────────────────────
ensure_ca() {
  section "🔐  Envaysoft Root CA"

  mkdir -p "$CA_DIR"

  local need_copy=0
  [[ -f "$CA_CRT" ]] || need_copy=1
  [[ -f "$CA_KEY" ]] || need_copy=1

  if (( need_copy )); then
    warn "Root CA not found in $CA_DIR"
    local src_crt="$SCRIPT_DIR/envaysoft-ca.crt"
    local src_key="$SCRIPT_DIR/envaysoft-ca.key"
    local src_srl="$SCRIPT_DIR/envaysoft-ca.srl"

    [[ -f "$src_crt" ]] || die "No CA cert to copy from: $src_crt"
    [[ -f "$src_key" ]] || die "No CA key to copy from:  $src_key"

    cp -f "$src_crt" "$CA_CRT"
    cp -f "$src_key" "$CA_KEY"
    [[ -f "$src_srl" ]] && cp -f "$src_srl" "$CA_SRL"
    chmod 644 "$CA_CRT"; chmod 600 "$CA_KEY"
    ok "Copied Root CA from ${CYAN}$SCRIPT_DIR${RESET} → ${CYAN}$CA_DIR${RESET}"
  else
    ok "Root CA present: ${CYAN}$CA_CRT${RESET}"
  fi

  local subj
  subj="$(openssl x509 -in "$CA_CRT" -noout -subject 2>/dev/null | sed 's/^subject=//')"
  kv "CA subject" "${PURPLE}${subj}${RESET}"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Detect available PHP-FPM sockets and let the user choose
# ─────────────────────────────────────────────────────────────────────────────
PHP_SOCK=""
choose_php() {
  section "🐘  PHP-FPM pool"

  local socks=() s
  for s in /run/php/php*-fpm.sock /var/run/php/php*-fpm.sock; do
    [[ -S "$s" ]] && socks+=("$s")
  done
  # de-duplicate (/run and /var/run often symlink)
  local seen="" uniq=()
  for s in "${socks[@]:-}"; do
    local base; base="$(basename "$s")"
    [[ "$seen" == *"|$base|"* ]] && continue
    seen+="|$base|"; uniq+=("$s")
  done
  socks=("${uniq[@]:-}")

  if (( ${#socks[@]} == 0 )); then
    warn "No PHP-FPM sockets auto-detected under /run/php."
    ask PHP_SOCK "Enter PHP-FPM socket path or 127.0.0.1:9000" "/run/php/php-fpm.sock"
    return
  fi

  say "  ${GREY}Detected PHP-FPM sockets:${RESET}"
  echo
  local i=1
  for s in "${socks[@]}"; do
    local ver; ver="$(basename "$s" | sed -E 's/php([0-9.]+)?-fpm.sock/\1/')"
    printf "    ${BOLD}${CYAN}%d${RESET}) ${WHITE}%s${RESET}  ${GREY}%s${RESET}\n" \
      "$i" "$s" "${ver:+PHP $ver}"
    ((i++))
  done
  echo
  local choice
  ask choice "Choose a socket number" "1"
  if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#socks[@]} )); then
    PHP_SOCK="${socks[choice-1]}"
  else
    PHP_SOCK="${socks[0]}"
  fi
  ok "Using ${CYAN}$PHP_SOCK${RESET}"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Collect vhost details
# ─────────────────────────────────────────────────────────────────────────────
DOMAIN=""; ALIASES=(); WEBROOT=""; ADD_HOSTS="N"
APP_TYPE="plain"; APP_LABEL="Plain PHP"; DOCROOT=""
collect_input() {
  section "🌍  Site details"

  while [[ -z "$DOMAIN" ]]; do
    ask DOMAIN "Primary domain (e.g. myapp.local)" ""
    if [[ ! "$DOMAIN" =~ ^[A-Za-z0-9.-]+$ ]]; then
      warn "Invalid domain. Use letters, numbers, dots and hyphens only."
      DOMAIN=""
    fi
  done

  echo
  if confirm "Add host aliases (extra domains in the same cert)?" "N"; then
    local raw
    ask raw "Aliases (space or comma separated)" ""
    raw="${raw//,/ }"
    read -r -a ALIASES <<<"$raw"
  fi

  echo
  ask WEBROOT "Project directory" "$WWW_ROOT/$DOMAIN"

  echo
  if confirm "Add ${BOLD}$DOMAIN${RESET}${WHITE} (and aliases) to /etc/hosts → 127.0.0.1?" "Y"; then
    ADD_HOSTS="Y"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  Application profile — sets document root + URL-rewrite rules
# ─────────────────────────────────────────────────────────────────────────────
choose_app() {
  section "🧩  Application type"
  say "  ${GREY}Pick a profile — it tunes the document root & URL-rewrite rules:${RESET}"
  echo
  printf "    ${BOLD}${CYAN}1${RESET}) ${WHITE}%-11s${RESET} ${GREY}%s${RESET}\n" "Plain PHP"  "serves project dir, /index.php fallback"
  printf "    ${BOLD}${CYAN}2${RESET}) ${WHITE}%-11s${RESET} ${GREY}%s${RESET}\n" "Laravel"    "root → public/, pretty-URL front controller"
  printf "    ${BOLD}${CYAN}3${RESET}) ${WHITE}%-11s${RESET} ${GREY}%s${RESET}\n" "WordPress"  "permalinks + upload PHP hardening"
  printf "    ${BOLD}${CYAN}4${RESET}) ${WHITE}%-11s${RESET} ${GREY}%s${RESET}\n" "Drupal"     "root → web/, clean URLs (D8/9/10)"
  printf "    ${BOLD}${CYAN}5${RESET}) ${WHITE}%-11s${RESET} ${GREY}%s${RESET}\n" "Static"     "static files only, no PHP"
  echo
  local c; ask c "Choose an application type" "1"
  case "$c" in
    2) APP_TYPE="laravel";   APP_LABEL="Laravel";   DOCROOT="$WEBROOT/public" ;;
    3) APP_TYPE="wordpress"; APP_LABEL="WordPress"; DOCROOT="$WEBROOT" ;;
    4) APP_TYPE="drupal";    APP_LABEL="Drupal";    DOCROOT="$WEBROOT/web" ;;
    5) APP_TYPE="static";    APP_LABEL="Static";    DOCROOT="$WEBROOT" ;;
    *) APP_TYPE="plain";     APP_LABEL="Plain PHP"; DOCROOT="$WEBROOT" ;;
  esac
  ok "Profile: ${GREEN}${BOLD}$APP_LABEL${RESET}"

  echo
  say "  ${GREY}${ITAL}The document root is the exact folder Nginx serves — override it for any custom layout.${RESET}"
  ask DOCROOT "Custom document root" "$DOCROOT"
  ok "Document root: ${YELLOW}$DOCROOT${RESET}"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Review screen
# ─────────────────────────────────────────────────────────────────────────────
review() {
  section "📋  Review"
  kv "Primary domain" "${GREEN}${BOLD}$DOMAIN${RESET}"
  if (( ${#ALIASES[@]} )); then
    kv "Aliases" "${CYAN}${ALIASES[*]}${RESET}"
  else
    kv "Aliases" "${GREY}none${RESET}"
  fi
  kv "Wildcard SAN" "${GREY}*.$DOMAIN${RESET}"
  kv "App profile" "${MAGENTA}${BOLD}$APP_LABEL${RESET}"
  kv "Project dir" "${YELLOW}$WEBROOT${RESET}"
  kv "Document root" "${ORANGE}$DOCROOT${RESET}"
  kv "PHP-FPM" "${PURPLE}$PHP_SOCK${RESET}"
  kv "Nginx conf" "${GREY}$NGINX_AVAILABLE/$DOMAIN${RESET}"
  kv "SSL cert" "${GREY}$CA_DIR/$DOMAIN.crt${RESET}"
  kv "Edit /etc/hosts" "$( [[ $ADD_HOSTS == Y ]] && echo "${GREEN}yes${RESET}" || echo "${GREY}no${RESET}" )"
  echo
  hr
  confirm "${BOLD}Proceed and create the vhost?${RESET}" "Y" || die "Aborted by user."
}

# ─────────────────────────────────────────────────────────────────────────────
#  SSL: build the .ext (SAN), CSR, key and sign with the Root CA
# ─────────────────────────────────────────────────────────────────────────────
generate_ssl() {
  section "🔏  SSL certificate"

  local key="$CA_DIR/$DOMAIN.key"
  local csr="$CA_DIR/$DOMAIN.csr"
  local ext="$CA_DIR/$DOMAIN.ext"
  local crt="$CA_DIR/$DOMAIN.crt"

  if [[ -f "$crt" ]]; then
    if ! confirm "Certificate for ${BOLD}$DOMAIN${RESET}${WHITE} exists. Regenerate?" "N"; then
      ok "Keeping existing certificate."
      return
    fi
  fi

  # Build SAN list: primary, wildcard, then each alias (+ its wildcard).
  local -a sans=("DNS:$DOMAIN" "DNS:*.$DOMAIN")
  local a
  for a in "${ALIASES[@]:-}"; do
    [[ -z "$a" ]] && continue
    sans+=("DNS:$a" "DNS:*.$a")
  done

  # Write the .ext file (matches existing Envaysoft convention)
  {
    echo "authorityKeyIdentifier=keyid,issuer"
    echo "basicConstraints=CA:FALSE"
    echo "keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment"
    echo "subjectAltName = @alt_names"
    echo ""
    echo "[alt_names]"
    local n=1 dns
    for dns in "$DOMAIN" "*.$DOMAIN"; do
      echo "DNS.$n = $dns"; ((n++))
    done
    for a in "${ALIASES[@]:-}"; do
      [[ -z "$a" ]] && continue
      echo "DNS.$n = $a"; ((n++))
      echo "DNS.$n = *.$a"; ((n++))
    done
  } > "$ext"
  ok "Wrote SAN extension → ${CYAN}$ext${RESET}"

  local subj="/C=BD/ST=Dhaka/L=Dhaka/O=Envaysoft/OU=IT/CN=$DOMAIN"

  spin "Generating 2048-bit private key & CSR" \
    openssl req -new -nodes -newkey rsa:2048 \
      -keyout "$key" -out "$csr" -subj "$subj" \
    || die "Key/CSR generation failed."

  # Sign with the Root CA (auto-create serial if absent)
  local srl_args=(-CAserial "$CA_SRL")
  [[ -f "$CA_SRL" ]] || srl_args=(-CAserial "$CA_SRL" -CAcreateserial)

  spin "Signing certificate with Envaysoft Root CA" \
    openssl x509 -req -in "$csr" \
      -CA "$CA_CRT" -CAkey "$CA_KEY" "${srl_args[@]}" \
      -out "$crt" -days "$CERT_DAYS" -sha256 -extfile "$ext" \
    || die "Certificate signing failed."

  chmod 600 "$key"; chmod 644 "$crt"
  ok "Certificate valid for ${BOLD}$CERT_DAYS${RESET} days"
  kv "SAN entries" "${GREY}${sans[*]}${RESET}"
}

# ─────────────────────────────────────────────────────────────────────────────
#  Web root scaffold
# ─────────────────────────────────────────────────────────────────────────────
make_webroot() {
  section "📁  Document root"
  if [[ -d "$DOCROOT" ]]; then
    ok "Directory exists: ${YELLOW}$DOCROOT${RESET}"
  else
    mkdir -p "$DOCROOT"
    ok "Created ${YELLOW}$DOCROOT${RESET}"
  fi

  # Frameworks ship their own front controller — never scaffold over them.
  if [[ "$APP_TYPE" != "plain" && "$APP_TYPE" != "static" ]]; then
    info "${GREY}Deploy your $APP_LABEL code into ${WEBROOT} — front controller expected at ${DOCROOT}.${RESET}"
    local owner="${SUDO_USER:-$USER}"
    chown -R "$owner":"$owner" "$WEBROOT" 2>/dev/null || true
    return
  fi

  # Static profile → a simple landing page
  if [[ "$APP_TYPE" == "static" ]]; then
    if [[ -z "$(ls -A "$DOCROOT" 2>/dev/null)" ]]; then
      cat > "$DOCROOT/index.html" <<HTML
<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$DOMAIN</title>
<style>body{margin:0;min-height:100vh;display:grid;place-items:center;
font-family:system-ui,sans-serif;background:linear-gradient(135deg,#6366f1,#ec4899,#f59e0b);color:#fff}
h1{font-size:2.4rem}</style></head>
<body><div><h1>🚀 $DOMAIN</h1><p>Static site live over HTTPS 🔒 — Envaysoft</p></div></body></html>
HTML
      local owner="${SUDO_USER:-$USER}"
      chown -R "$owner":"$owner" "$WEBROOT" 2>/dev/null || true
      ok "Added a starter ${CYAN}index.html${RESET}"
    fi
    return
  fi

  # Plain PHP → drop a friendly index.php only if the directory is empty
  if [[ -z "$(ls -A "$DOCROOT" 2>/dev/null)" ]]; then
    cat > "$DOCROOT/index.php" <<PHP
<?php
header('Content-Type: text/html; charset=utf-8');
?>
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>$DOMAIN · Envaysoft</title>
  <style>
    body{margin:0;min-height:100vh;display:grid;place-items:center;
         font-family:system-ui,Segoe UI,Roboto,sans-serif;
         background:linear-gradient(135deg,#6366f1,#ec4899,#f59e0b);color:#fff}
    .card{background:rgba(0,0,0,.25);padding:3rem 4rem;border-radius:1.5rem;
          backdrop-filter:blur(8px);text-align:center;box-shadow:0 20px 60px rgba(0,0,0,.3)}
    h1{margin:.2rem 0;font-size:2.4rem}
    code{background:rgba(255,255,255,.2);padding:.2rem .5rem;border-radius:.4rem}
    p{opacity:.9}
  </style>
</head>
<body>
  <div class="card">
    <h1>🚀 $DOMAIN</h1>
    <p>Your Nginx + PHP-FPM vhost is live over <strong>HTTPS 🔒</strong></p>
    <p>PHP <code><?= PHP_VERSION ?></code> · served from <code>$DOCROOT</code></p>
    <p style="margin-top:1.5rem;opacity:.7">— Envaysoft —</p>
  </div>
</body>
</html>
PHP
    # Hand ownership to the invoking (non-root) user where possible
    local owner="${SUDO_USER:-$USER}"
    chown -R "$owner":"$owner" "$WEBROOT" 2>/dev/null || true
    ok "Added a starter ${CYAN}index.php${RESET}"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  App-specific location / URL-rewrite block (emitted into the vhost)
#  NB: \$ escapes shell expansion so nginx keeps its own variables;
#      $PHP_SOCK is intentionally expanded by the shell.
# ─────────────────────────────────────────────────────────────────────────────
emit_app_block() {
  # Shared PHP-FPM handler (Laravel / WordPress / plain)
  local php_block
  php_block=$(cat <<NGINX
    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:$PHP_SOCK;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT \$realpath_root;
    }
NGINX
)

  case "$APP_TYPE" in
    laravel)
      cat <<NGINX
    index index.php;

    # Laravel front controller — pretty URLs / route rewriting
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

$php_block
    # Deny dotfiles (.env, .git …) but keep ACME challenges reachable
    location ~ /\.(?!well-known).* { deny all; }
NGINX
      ;;

    wordpress)
      cat <<NGINX
    index index.php;

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; allow all; }

    # WordPress permalinks / URL rewriting
    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

$php_block
    # Cache static assets aggressively
    location ~* \.(js|css|png|jpe?g|gif|ico|svg|webp|woff2?)\$ {
        expires max; log_not_found off; access_log off;
    }

    # Harden: never execute PHP inside uploads
    location ~* /(?:uploads|files)/.*\.php\$ { deny all; }
    location ~ /\.(?!well-known).* { deny all; }
NGINX
      ;;

    drupal)
      cat <<NGINX
    index index.php;

    location = /favicon.ico { log_not_found off; access_log off; }
    location = /robots.txt  { allow all; log_not_found off; access_log off; }

    # Drupal clean URLs
    location / {
        try_files \$uri /index.php?\$query_string;
    }

    location @rewrite {
        rewrite ^ /index.php;
    }

    # PHP only for front controller / core scripts (with PATH_INFO support)
    location ~ '\.php\$|^/update.php' {
        fastcgi_split_path_info ^(.+?\.php)(|/.*)\$;
        set \$path_info \$fastcgi_path_info;
        try_files \$fastcgi_script_name =404;
        include fastcgi_params;
        fastcgi_pass unix:$PHP_SOCK;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        fastcgi_param DOCUMENT_ROOT \$realpath_root;
        fastcgi_param PATH_INFO \$path_info;
        fastcgi_intercept_errors on;
    }

    # Static assets fall back to the rewrite handler
    location ~* \.(js|css|png|jpe?g|gif|ico|svg|webp|woff2?)\$ {
        try_files \$uri @rewrite;
        expires max; log_not_found off;
    }

    # Security hardening
    location ~ \..*/.*\.php\$               { return 403; }
    location ~ ^/sites/.*/private/          { return 403; }
    location ~ ^/sites/[^/]+/files/.*\.php\$ { deny all; }
    location ~ /vendor/.*\.php\$            { deny all; return 404; }
    location ~ (^|/)\.(?!well-known)        { return 403; }
NGINX
      ;;

    static)
      cat <<NGINX
    index index.html index.htm;

    # Static files with SPA-friendly fallback
    location / {
        try_files \$uri \$uri/ =404;
    }

    location ~* \.(js|css|png|jpe?g|gif|ico|svg|webp|woff2?)\$ {
        expires max; log_not_found off; access_log off;
    }

    location ~ /\.(?!well-known).* { deny all; }
NGINX
      ;;

    *) # plain PHP
      cat <<NGINX
    index index.php index.html index.htm;

    # Generic pretty-URL rewriting via front controller
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

$php_block
    location ~ /\.(?!well-known).* { deny all; }
NGINX
      ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────────────
#  Nginx vhost config
# ─────────────────────────────────────────────────────────────────────────────
write_vhost() {
  section "⚙️  Nginx vhost"

  local conf="$NGINX_AVAILABLE/$DOMAIN"
  local server_names="$DOMAIN"
  local a
  for a in "${ALIASES[@]:-}"; do
    [[ -n "$a" ]] && server_names+=" $a"
  done

  mkdir -p "$NGINX_AVAILABLE" "$NGINX_ENABLED"

  if [[ -f "$conf" ]]; then
    confirm "Vhost config exists. Overwrite?" "Y" || die "Aborted — config kept."
  fi

  cat > "$conf" <<NGINX
# ─────────────────────────────────────────────────────────────
#  $DOMAIN  —  generated by Envaysoft create-vhost.sh
# ─────────────────────────────────────────────────────────────

# HTTP → HTTPS redirect
server {
    listen 80;
    listen [::]:80;
    server_name $server_names;
    return 301 https://\$host\$request_uri;
}

# HTTPS server
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
    server_name $server_names;

    root $DOCROOT;
    charset utf-8;

    # ── SSL (Envaysoft Root CA) ──────────────────────────────
    ssl_certificate     $CA_DIR/$DOMAIN.crt;
    ssl_certificate_key $CA_DIR/$DOMAIN.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_cache   shared:SSL:10m;
    ssl_session_timeout 10m;

    # ── Logging ──────────────────────────────────────────────
    access_log /var/log/nginx/$DOMAIN.access.log;
    error_log  /var/log/nginx/$DOMAIN.error.log;

    client_max_body_size 64M;

NGINX

  # ── App-specific routing / URL-rewrite block ───────────────
  emit_app_block >> "$conf"

  printf '}\n' >> "$conf"

  ok "Wrote ${CYAN}$conf${RESET} ${GREY}($APP_LABEL profile)${RESET}"

  ln -sfn "$conf" "$NGINX_ENABLED/$DOMAIN"
  ok "Enabled (symlinked into ${CYAN}$NGINX_ENABLED${RESET})"
}

# ─────────────────────────────────────────────────────────────────────────────
#  /etc/hosts entry
# ─────────────────────────────────────────────────────────────────────────────
update_hosts() {
  [[ "$ADD_HOSTS" == "Y" ]] || return 0
  section "🧭  /etc/hosts"

  local names="$DOMAIN" a
  for a in "${ALIASES[@]:-}"; do [[ -n "$a" ]] && names+=" $a"; done

  local added=()
  for h in $names; do
    if grep -qE "^[^#]*[[:space:]]$h(\$|[[:space:]])" "$HOSTS_FILE"; then
      info "${GREY}$h already in /etc/hosts${RESET}"
    else
      printf '127.0.0.1\t%s\n' "$h" >> "$HOSTS_FILE"
      added+=("$h")
    fi
  done
  (( ${#added[@]} )) && ok "Added: ${CYAN}${added[*]}${RESET}" || true
}

# ─────────────────────────────────────────────────────────────────────────────
#  Test config & reload nginx
# ─────────────────────────────────────────────────────────────────────────────
reload_nginx() {
  section "🔁  Activate"

  if ! spin "Testing nginx configuration" nginx -t; then
    die "nginx config test failed — vhost written but NOT reloaded. Fix and run 'nginx -t'."
  fi

  if command -v systemctl >/dev/null 2>&1; then
    spin "Reloading nginx (systemctl)" systemctl reload nginx || \
      spin "Restarting nginx" systemctl restart nginx || warn "Could not reload nginx automatically."
  else
    spin "Reloading nginx" nginx -s reload || warn "Could not reload nginx automatically."
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
#  Final summary
# ─────────────────────────────────────────────────────────────────────────────
finish() {
  echo
  hr
  say "  ${GREEN}${BOLD}🎉  All done!${RESET}  Your site is ready."
  echo
  kv "URL" "${CYAN}${BOLD}https://$DOMAIN${RESET}"
  local a
  for a in "${ALIASES[@]:-}"; do
    [[ -n "$a" ]] && kv "Alias URL" "${CYAN}https://$a${RESET}"
  done
  kv "App profile" "${MAGENTA}$APP_LABEL${RESET}"
  kv "Project dir" "${YELLOW}$WEBROOT${RESET}"
  kv "Document root" "${ORANGE}$DOCROOT${RESET}"
  kv "Vhost" "${GREY}$NGINX_AVAILABLE/$DOMAIN${RESET}"
  kv "Certificate" "${GREY}$CA_DIR/$DOMAIN.crt${RESET}"
  echo
  say "  ${GREY}${ITAL}Tip: trust ${CA_CRT} in your browser/OS to remove warnings.${RESET}"
  hr
  echo
}

# ─────────────────────────────────────────────────────────────────────────────
#  Main
# ─────────────────────────────────────────────────────────────────────────────
main() {
  ensure_root "$@"
  banner
  check_deps
  ensure_ca
  collect_input
  choose_app
  choose_php
  review
  generate_ssl
  make_webroot
  write_vhost
  update_hosts
  reload_nginx
  finish
}

main "$@"

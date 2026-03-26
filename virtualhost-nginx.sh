#!/usr/bin/env bash
set -Eeuo pipefail

# =========================
# BASE CONFIGURATION
# =========================

readonly EMAIL="webmaster@localhost"
readonly USER_DIR="/var/www"
readonly HOSTS_FILE="/etc/hosts"
readonly WSL_HOSTS_FILE="/mnt/c/Windows/System32/drivers/etc/hosts"

# =========================
# SYSTEM DETECTION
# =========================

get_distro_family() {
  [[ -f /etc/os-release ]] || { echo "unknown"; return; }
  . /etc/os-release

  case "$ID" in
    ubuntu|debian) echo "debian" ;;
    centos|rhel|rocky|almalinux|fedora) echo "rhel" ;;
    *)
      [[ "${ID_LIKE:-}" == *debian* ]] && echo "debian" && return
      [[ "${ID_LIKE:-}" == *rhel* ]] && echo "rhel" && return
      echo "unknown"
      ;;
  esac
}

is_wsl() {
  grep -qi microsoft /proc/version 2>/dev/null && return 0
  grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null && return 0
  return 1
}

# =========================
# UTILS
# =========================

die() {
  printf "ERROR: %s\n" "$1" >&2
  exit 1
}

info() {
  printf "%s\n" "$1"
}

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "Must be run as root (use sudo)"
}

detect_nginx_user() {
  local user
  user=$(ps -eo user,comm | awk '/nginx/ && $1!="root" {print $1; exit}')
  echo "${user:-www-data}"
}

sanitize_domain() {
  local domain="$1"

  [[ ${#domain} -le 253 ]] || die "Domain too long"

  if [[ ! "$domain" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]; then
    die "Invalid domain name: $domain"
  fi
}

is_root_domain() {
  [[ "$(awk -F. '{print NF}' <<< "$1")" -eq 2 ]]
}

reload_nginx() {
  if [[ "$IS_WSL" == "true" ]]; then
    nginx -s reload
  else
    systemctl reload "$NGINX_SERVICE"
  fi
}

is_dir_empty() {
  local dir="$1"

  [[ -d "$dir" ]] || return 2

  shopt -s nullglob dotglob
  local files=("$dir"/*)
  shopt -u nullglob dotglob

  (( ${#files[@]} == 0 ))
}

enable_host() {
  if [[ "$DISTRO_FAMILY" == "debian" ]]; then
    ln -sf "$SITES_AVAILABLE/$DOMAIN.conf" "$SITES_ENABLED/$DOMAIN.conf"
  fi

  nginx -t || die "Nginx configuration test failed"
}

disable_host() {
  rm -f "$SITES_ENABLED/$DOMAIN.conf"
}

# =========================
# ENVIRONMENT SETUP BY DISTRO
# =========================
readonly DISTRO_FAMILY="$(get_distro_family)"
readonly IS_WSL="$(is_wsl && echo true || echo false)"
readonly NGINX_SERVICE="nginx"

if [[ "$DISTRO_FAMILY" == "rhel" ]]; then
  readonly SITES_AVAILABLE="/etc/nginx/conf.d"
  readonly SITES_ENABLED="/etc/nginx/conf.d"
elif [[ "$DISTRO_FAMILY" == "debian" ]]; then
  readonly SITES_AVAILABLE="/etc/nginx/sites-available"
  readonly SITES_ENABLED="/etc/nginx/sites-enabled"
else
  die "Unsupported distro"
fi

# =========================
# HOSTS MANAGEMENT
# =========================

add_host_entry() {
  local domain="$1"

  grep -q "[[:space:]]$domain\$" "$HOSTS_FILE" || \
    echo "127.0.0.1 $domain" >> "$HOSTS_FILE"

  if [[ "$IS_SUBDOMAIN" == "false" ]] && is_root_domain "$domain"; then
    grep -q "[[:space:]]www.$domain\$" "$HOSTS_FILE" || \
      echo "127.0.0.1 www.$domain" >> "$HOSTS_FILE"
  fi

  if [[ "$IS_WSL" == "true" && -w "$WSL_HOSTS_FILE" ]]; then
    echo "127.0.0.1 $domain" >> "$WSL_HOSTS_FILE"
    if [[ "$IS_SUBDOMAIN" == "false" ]] && is_root_domain "$domain"; then
      echo "127.0.0.1 www.$domain" >> "$WSL_HOSTS_FILE"
    fi
  fi
}

remove_host_entry() {
  local domain="$1"

  sed -i "\|[[:space:]]$domain\$|d" "$HOSTS_FILE"

  if [[ "$IS_SUBDOMAIN" == "false" ]] && is_root_domain "$domain"; then
    sed -i "\|[[:space:]]www.$domain\$|d" "$HOSTS_FILE"
  fi

  if [[ "$IS_WSL" == "true" && -w "$WSL_HOSTS_FILE" ]]; then
    sed -i "\|[[:space:]]$domain\$|d" "$WSL_HOSTS_FILE"
    if [[ "$IS_SUBDOMAIN" == "false" ]] && is_root_domain "$domain"; then
      sed -i "\|[[:space:]]www.$domain\$|d" "$WSL_HOSTS_FILE"
    fi
  fi
}

# =========================
# PARAMETERS & VALIDATION
# =========================

ACTION="${1:-}"
DOMAIN="${2:-}"
ROOT_DIR_INPUT="${3:-}"
IS_SUBDOMAIN="${4:-false}"
CANONICAL="${5:-root}"

# force domain name downcase 
# for consistency
DOMAIN="${DOMAIN,,}"

require_root

[[ "$ACTION" == "create" || "$ACTION" == "delete" ]] || \
  die "Use: $0 {create|delete} domain [root_dir] [is_subdomain] [canonical]"

while [[ -z "$DOMAIN" ]]; do
  read -rp "Type domain: " DOMAIN
done

sanitize_domain "$DOMAIN"

case "$IS_SUBDOMAIN" in true|false) ;; *) die "is_subdomain must be true or false" ;; esac
case "$CANONICAL" in root|www) ;; *) die "canonical must be root or www" ;; esac

ROOT_DIR="${ROOT_DIR_INPUT:-${DOMAIN//./}}"
[[ "$ROOT_DIR" == /* ]] || ROOT_DIR="$USER_DIR/$ROOT_DIR"

readonly VHOST_FILE="$SITES_AVAILABLE/$DOMAIN.conf"
readonly NGINX_USER="$(detect_nginx_user)"

# =========================
# CREATE
# =========================

create_vhost() {
  [[ ! -f "$VHOST_FILE" ]] || die "Domain exists"

   if [[ ! -d "$ROOT_DIR" ]]; then
    mkdir -p "$ROOT_DIR"
    chmod 755 "$ROOT_DIR"
  fi

  if [[is_dir_empty "$ROOT_DIR" ]]; then
    cat > "$ROOT_DIR/index.html" <<EOF
<html><body><h1>Welcome to $DOMAIN</h1></body></html>
EOF
    cat > "$ROOT_DIR/phpinfo.php" <<EOF
<?php phpinfo(); ?>
EOF
  fi

  # Canonical domain
  CANONICAL_DOMAIN="$DOMAIN"
  if [[ "$IS_SUBDOMAIN" == "false" ]] && is_root_domain "$DOMAIN" && [[ "$CANONICAL" == "www" ]]; then
    CANONICAL_DOMAIN="www.$DOMAIN"
  fi

  cat > "$VHOST_FILE" <<EOF
# === METADATA ===
# is_subdomain=$IS_SUBDOMAIN
# canonical=$CANONICAL
# root_dir=$ROOT_DIR
# === /METADATA ===

server {
    listen 80;
    server_name $CANONICAL_DOMAIN$([[ "$IS_SUBDOMAIN" == "false" && is_root_domain "$DOMAIN" ]] && echo " $DOMAIN www.$DOMAIN");

    root $ROOT_DIR;
    index index.html index.htm;

    # serve static files directly
    location ~* \.(jpg|jpeg|gif|css|png|js|ico|html)$ {
      access_log off;
      expires max;
    }

    # removes trailing slashes (prevents SEO duplicate content issues)
    if (!-d \$request_filename) {
      rewrite ^/(.+)/\$ /\$1 permanent;
    }

    # removes trailing 'index' from all controllers
    if (\$request_uri ~* index/?\$) {
      rewrite ^/(.*)/index/?\$ /\$1 permanent;
    }

    # catch all 404 errors and route to index.php
    # (for frameworks like Laravel, Symfony, etc.)
    error_page 404 /index.php;

    location ~ \.php$ {
      fastcgi_split_path_info ^(.+\.php)(/.+)\$;
      fastcgi_pass 127.0.0.1:9000;
      fastcgi_index index.php;
      include fastcgi_params;
    }

    location ~ /\.ht {
      deny all;
    }

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

  add_host_entry "$DOMAIN"
  chown -R "$NGINX_USER:$NGINX_USER" "$ROOT_DIR" 2>/dev/null || true
  enable_host
  reload_nginx
  info "Nginx server block created: http://$CANONICAL_DOMAIN"
}

# =========================
# DELETE
# =========================

load_metadata() {
  IS_SUBDOMAIN="$(grep -oP '(?<=is_subdomain=).*' "$VHOST_FILE" || echo false)"
  CANONICAL="$(grep -oP '(?<=canonical=).*' "$VHOST_FILE" || echo root)"
  ROOT_DIR="$(grep -oP '(?<=root_dir=).*' "$VHOST_FILE" || echo "")"
}

delete_vhost() {
  [[ -f "$VHOST_FILE" ]] || die "Domain does not exist"
  load_metadata
  remove_host_entry "$DOMAIN"
  disable_host
  reload_nginx
  rm -f "$VHOST_FILE"

  [[ -d "$ROOT_DIR" ]] && read -rp "Delete directory $ROOT_DIR? (y/N): " confirm && [[ "$confirm" =~ ^[Yy]$ ]] && rm -rf "$ROOT_DIR"
  info "Nginx server block deleted: $DOMAIN"
}

# =========================
# MAIN
# =========================

case "$ACTION" in
  create) create_vhost ;;
  delete) delete_vhost ;;
esac

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

detect_apache_user() {
  ps -eo user,comm | awk '/(apache2|httpd)/ && $1!="root" {print $1; exit}'
}

sanitize_domain() {
  [[ "$1" =~ ^[a-zA-Z0-9.-]+$ ]] || die "Invalid domain name: $1"
}

is_root_domain() {
  [[ "$(awk -F. '{print NF}' <<< "$1")" -eq 2 ]]
}

reload_apache() {
  systemctl reload "$APACHE_SERVICE"
}

enable_host() {
  if [[ "$DISTRO_FAMILY" == "debian" ]]; then
    a2ensite "$DOMAIN" >/dev/null
  elif [[ "$DISTRO_FAMILY" == "rhel" ]]; then
    ln -s "$SITES_AVAILABLE/$DOMAIN.conf" "$SITES_ENABLED/$DOMAIN.conf"
  fi
}

disable_host() {
  if [[ "$DISTRO_FAMILY" == "debian" ]]; then
    a2dissite "$DOMAIN" >/dev/null
  elif [[ "$DISTRO_FAMILY" == "rhel" ]]; then
    rm -f "$SITES_ENABLED/$DOMAIN.conf"
  fi
}

# =========================
# ENVIRONMENT SETUP BY DISTRO
# =========================
readonly DISTRO_FAMILY="$(get_distro_family)"
readonly IS_WSL="$(is_wsl && echo true || echo false)"

if [[ "$DISTRO_FAMILY" == "rhel" ]]; then
  readonly APACHE_SERVICE="httpd"
  readonly SITES_AVAILABLE="/etc/httpd/sites-available"
  readonly SITES_ENABLED="/etc/httpd/sites-enabled"
elif [[ "$DISTRO_FAMILY" == "debian" ]]; then
  readonly APACHE_SERVICE="apache2"
  readonly SITES_AVAILABLE="/etc/apache2/sites-available"
  readonly SITES_ENABLED="/etc/apache2/sites-enabled"
else
  die "Unsupported Linux distribution. Only Debian-based and RHEL-based distros are supported."
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
readonly APACHE_USER="$(detect_apache_user)"

# =========================
# CREATE
# =========================

create_vhost() {
  [[ ! -f "$VHOST_FILE" ]] || die "Domain already exists"

  mkdir -p "$ROOT_DIR"
  chmod 755 "$ROOT_DIR"

  cat > "$ROOT_DIR/phpinfo.php" <<EOF
<?php phpinfo(); ?>
EOF

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

<VirtualHost *:80>
  ServerAdmin $EMAIL
  ServerName $CANONICAL_DOMAIN
EOF

  if [[ "$IS_SUBDOMAIN" == "false" ]] && is_root_domain "$DOMAIN"; then
    if [[ "$CANONICAL" == "www" ]]; then
      echo "  ServerAlias $DOMAIN" >> "$VHOST_FILE"
    else
      echo "  ServerAlias www.$DOMAIN" >> "$VHOST_FILE"
    fi
  fi

  cat >> "$VHOST_FILE" <<EOF

  DocumentRoot $ROOT_DIR

  <Directory $ROOT_DIR>
    AllowOverride All
    Require all granted
  </Directory>

  RewriteEngine On
EOF

  if [[ "$IS_SUBDOMAIN" == "false" ]] && is_root_domain "$DOMAIN"; then
    if [[ "$CANONICAL" == "www" ]]; then
      cat >> "$VHOST_FILE" <<EOF
  RewriteCond %{HTTP_HOST} ^$DOMAIN\$ [NC]
  RewriteRule ^(.*)$ http://www.$DOMAIN/\$1 [R=301,L]
EOF
    else
      cat >> "$VHOST_FILE" <<EOF
  RewriteCond %{HTTP_HOST} ^www\\.$DOMAIN\$ [NC]
  RewriteRule ^(.*)$ http://$DOMAIN/\$1 [R=301,L]
EOF
    fi
  fi

  cat >> "$VHOST_FILE" <<EOF

  ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}-error.log
  CustomLog \${APACHE_LOG_DIR}/${DOMAIN}-access.log combined
</VirtualHost>
EOF

  add_host_entry "$DOMAIN"

  chown -R "${APACHE_USER:-www-data}:${APACHE_USER:-www-data}" "$ROOT_DIR"

  enable_host
  reload_apache

  info "VirtualHost created: http://$CANONICAL_DOMAIN"
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
  [[ -f "$VHOST_FILE" ]] || die "The specified domain does not exist."

  load_metadata

  remove_host_entry "$DOMAIN"

  disable_host
  reload_apache

  rm -f "$VHOST_FILE"

  if [[ -d "$ROOT_DIR" ]]; then
    read -rp "Delete directory $ROOT_DIR? (y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] && rm -rf "$ROOT_DIR"
  fi

  info "VirtualHost deleted: $DOMAIN"
}

# =========================
# MAIN
# =========================

case "$ACTION" in
  create) create_vhost ;;
  delete) delete_vhost ;;
esac

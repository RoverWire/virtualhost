#!/bin/bash
set -Eeuo pipefail


# =========================
# CONFIGURACIÓN
# =========================

readonly EMAIL="webmaster@localhost"
readonly SITES_AVAILABLE="/etc/apache2/sites-available"
readonly USER_DIR="/var/www"
readonly HOSTS_FILE="/etc/hosts"
readonly APACHE_SERVICE="apache2"

# =========================
# UTILIDADES
# =========================

die() {
  printf "ERROR: %s\n" "$1" >&2
  exit 1
}

info() {
  printf "%s\n" "$1"
}

require_root() {
  [[ "$(id -u)" -eq 0 ]] || die "Debe ejecutarse como root (use sudo)"
}

detect_apache_user() {
  ps -eo user,comm | awk '/(apache2|httpd)/ && $1!="root" {print $1; exit}'
}

sanitize_domain() {
  [[ "$1" =~ ^[a-zA-Z0-9.-]+$ ]] || die "Dominio inválido"
}

is_root_domain() {
  [[ "$(awk -F. '{print NF}' <<< "$1")" -eq 2 ]]
}

reload_apache() {
  systemctl reload "$APACHE_SERVICE"
}

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
}

remove_host_entry() {
  local domain="$1"

  sed -i "\|[[:space:]]$domain\$|d" "$HOSTS_FILE"

  if [[ "$IS_SUBDOMAIN" == "false" ]] && is_root_domain "$domain"; then
    sed -i "\|[[:space:]]www.$domain\$|d" "$HOSTS_FILE"
  fi
}

# =========================
# PARÁMETROS
# =========================

ACTION="${1:-}"
DOMAIN="${2:-}"
ROOT_DIR_INPUT="${3:-}"
IS_SUBDOMAIN="${4:-false}"
CANONICAL="${5:-root}"

require_root

[[ "$ACTION" == "create" || "$ACTION" == "delete" ]] || \
  die "Uso: $0 {create|delete} dominio [root_dir] [is_subdomain] [canonical]"

while [[ -z "$DOMAIN" ]]; do
  read -rp "Ingrese el dominio: " DOMAIN
done

sanitize_domain "$DOMAIN"

case "$IS_SUBDOMAIN" in true|false) ;; *) die "is_subdomain debe ser true o false" ;; esac
case "$CANONICAL" in root|www) ;; *) die "canonical debe ser root o www" ;; esac

ROOT_DIR="${ROOT_DIR_INPUT:-${DOMAIN//./}}"
[[ "$ROOT_DIR" == /* ]] || ROOT_DIR="$USER_DIR/$ROOT_DIR"

readonly VHOST_FILE="$SITES_AVAILABLE/$DOMAIN.conf"
readonly APACHE_USER="$(detect_apache_user)"

# =========================
# CREATE
# =========================

create_vhost() {
  [[ ! -f "$VHOST_FILE" ]] || die "El dominio ya existe"

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

  a2ensite "$DOMAIN" >/dev/null
  reload_apache

  info "VirtualHost creado: http://$CANONICAL_DOMAIN"
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
  [[ -f "$VHOST_FILE" ]] || die "El dominio no existe"

  load_metadata

  remove_host_entry "$DOMAIN"

  a2dissite "$DOMAIN" >/dev/null
  reload_apache

  rm -f "$VHOST_FILE"

  if [[ -d "$ROOT_DIR" ]]; then
    read -rp "¿Eliminar directorio $ROOT_DIR? (y/N): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] && rm -rf "$ROOT_DIR"
  fi

  info "VirtualHost eliminado: $DOMAIN"
}

# =========================
# MAIN
# =========================

case "$ACTION" in
  create) create_vhost ;;
  delete) delete_vhost ;;
esac

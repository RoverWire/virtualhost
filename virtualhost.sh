#!/bin/bash
set -Eeuo pipefail

### =========================
### CONFIGURACIÓN
### =========================

readonly EMAIL="webmaster@localhost"
readonly SITES_AVAILABLE="/etc/apache2/sites-available"
readonly USER_DIR="/var/www"
readonly HOSTS_FILE="/etc/hosts"
readonly APACHE_SERVICE="apache2"

### =========================
### UTILIDADES
### =========================

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

add_host_entry() {
  local domain="$1"
  grep -q "$domain" "$HOSTS_FILE" || echo "127.0.0.1 $domain" >> "$HOSTS_FILE"
}

remove_host_entry() {
  local domain="$1"
  sed -i "\|$domain|d" "$HOSTS_FILE"
}

reload_apache() {
  systemctl reload "$APACHE_SERVICE"
}

### =========================
### PARÁMETROS
### =========================

ACTION="${1:-}"
DOMAIN="${2:-}"
ROOT_DIR_INPUT="${3:-}"

require_root

[[ "$ACTION" == "create" || "$ACTION" == "delete" ]] || \
  die "Uso: $0 {create|delete} dominio [directorio]"

while [[ -z "$DOMAIN" ]]; do
  read -rp "Ingrese el dominio: " DOMAIN
done

sanitize_domain "$DOMAIN"

ROOT_DIR="${ROOT_DIR_INPUT:-${DOMAIN//./}}"
[[ "$ROOT_DIR" == /* ]] || ROOT_DIR="$USER_DIR/$ROOT_DIR"

readonly VHOST_FILE="$SITES_AVAILABLE/$DOMAIN.conf"
readonly APACHE_USER="$(detect_apache_user)"

### =========================
### CREATE
### =========================

create_vhost() {
  [[ ! -f "$VHOST_FILE" ]] || die "El dominio ya existe"

  mkdir -p "$ROOT_DIR"
  chmod 755 "$ROOT_DIR"

  cat > "$ROOT_DIR/phpinfo.php" <<EOF
<?php phpinfo(); ?>
EOF

  cat > "$VHOST_FILE" <<EOF
<VirtualHost *:80>
  ServerAdmin $EMAIL
  ServerName $DOMAIN
  DocumentRoot $ROOT_DIR

  <Directory $ROOT_DIR>
    AllowOverride All
    Require all granted
  </Directory>

  ErrorLog \${APACHE_LOG_DIR}/${DOMAIN}-error.log
  CustomLog \${APACHE_LOG_DIR}/${DOMAIN}-access.log combined
</VirtualHost>
EOF

  add_host_entry "$DOMAIN"

  chown -R "${APACHE_USER:-www-data}:${APACHE_USER:-www-data}" "$ROOT_DIR"

  a2ensite "$DOMAIN" >/dev/null
  reload_apache

  info "VirtualHost creado: http://$DOMAIN"
  info "Directorio: $ROOT_DIR"
}

### =========================
### DELETE
### =========================

delete_vhost() {
  [[ -f "$VHOST_FILE" ]] || die "El dominio no existe"

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

### =========================
### MAIN
### =========================

case "$ACTION" in
  create) create_vhost ;;
  delete) delete_vhost ;;
esac

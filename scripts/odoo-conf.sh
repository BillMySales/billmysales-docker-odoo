#!/bin/sh
# Writes the Odoo configuration file ($ODOO_RC) from the environment. Sourced
# by entrypoint.sh and setup.sh, so every container gets the same settings
# without secrets in a file of the repository.
set -eu

# Odoo's default mail server (the one in this file) only knows STARTTLS
# (smtp_ssl = True); setup.sh warns about SMTP_SECURE=ssl.
case "$(echo "${SMTP_SECURE:-}" | tr '[:upper:]' '[:lower:]')" in
    tls) smtp_ssl=True ;;
    *) smtp_ssl=False ;;
esac

# Odoo skips (with a warning) an addons directory without any module in it.
addons_path=
for manifest in /mnt/extra-addons/*/__manifest__.py; do
    if [ -f "${manifest}" ]; then
        addons_path=/mnt/extra-addons
        break
    fi
done

umask 077
# shellcheck disable=SC2153 # every variable is set by compose
cat > "${ODOO_RC}" <<CONF
[options]
; Generated from the environment on every container start (scripts/odoo-conf.sh).
data_dir = /var/lib/odoo
db_host = ${DB_HOST}
db_port = ${DB_PORT}
db_user = ${DB_USER}
db_password = ${DB_PASSWORD}
db_name = ${ODOO_DB}
; One database only; no database manager (create/drop/backup from the web).
dbfilter = ^${ODOO_DB}\$
list_db = False
admin_passwd = ${ODOO_MASTER_PASSWORD}
; Behind Caddy (and maybe Traefik): trust X-Forwarded-* headers.
proxy_mode = True
; Reached by Caddy from another container.
http_interface = 0.0.0.0
workers = ${ODOO_WORKERS}
max_cron_threads = ${ODOO_CRON_THREADS}
gevent_port = 8072
limit_memory_soft = ${ODOO_LIMIT_MEMORY_SOFT}
limit_memory_hard = ${ODOO_LIMIT_MEMORY_HARD}
limit_time_cpu = ${ODOO_LIMIT_TIME_CPU}
limit_time_real = ${ODOO_LIMIT_TIME_REAL}
without_demo = True
log_level = ${ODOO_LOG_LEVEL}
smtp_server = ${SMTP_HOST:-localhost}
smtp_port = ${SMTP_PORT:-25}
smtp_ssl = ${smtp_ssl}
CONF

# Optional settings, only when set.
add_option() {
    if [ -n "$2" ]; then
        printf '%s = %s\n' "$1" "$2" >> "${ODOO_RC}"
    fi
}
add_option addons_path "${addons_path}"
add_option smtp_user "${SMTP_USER:-}"
add_option smtp_password "${SMTP_PASSWORD:-}"
add_option email_from "${SMTP_FROM:-}"
add_option dev_mode "${ODOO_DEV:-}"

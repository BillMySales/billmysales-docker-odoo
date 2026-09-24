#!/bin/sh
# Initializes or upgrades the Odoo database and applies the stack's
# environment. Runs on every `docker compose up` and is safe to repeat:
# - Empty database: creates it with the `base` module and the ODOO_LANG
#   language (no demo data), then initial settings (company country and
#   currency, admin user; scripts/initial.py).
# - Installs the ODOO_MODULES that aren't installed yet (after the initial
#   settings, so `account` installs the country's localization).
# - New image (ODOO_VERSION changed): updates all modules (`-u all`). A new
#   major version is refused: that needs Odoo's upgrade process.
# - URL and PDF report settings from the environment (scripts/environment.py).
set -eu

STACK=/usr/local/share/stack/scripts
# shellcheck source=/dev/null
. "${STACK}/odoo-conf.sh"

odoo_cli() { odoo -c "${ODOO_RC}" -d "${ODOO_DB}" --no-http --workers=0 --max-cron-threads=0 "$@"; }
odoo_shell() { odoo shell -c "${ODOO_RC}" -d "${ODOO_DB}" --no-http < "$1"; }
db() { python3 "${STACK}/db.py" "$@"; }

if [ "$(echo "${SMTP_SECURE:-}" | tr '[:upper:]' '[:lower:]')" = ssl ]; then
    echo "WARNING: SMTP_SECURE=ssl is not supported by Odoo's default mail server" \
        "(STARTTLS only): use SMTP_SECURE=tls with port 587, or add the server" \
        "in Settings > Technical > Outgoing Mail Servers." >&2
fi

wait-for-psql.py --db_host="${DB_HOST}" --db_port="${DB_PORT}" \
    --db_user="${DB_USER}" --db_password="${DB_PASSWORD}" --timeout=60

# Separate assignments: with `set -e`, a failing helper aborts setup here.
installed="$(db installed)"
if [ -z "${installed}" ]; then
    echo "==> Creating database ${ODOO_DB} (Odoo ${ODOO_VERSION}, ${ODOO_LANG})"
    odoo_cli -i base --load-language="${ODOO_LANG}" --without-demo=True --stop-after-init
    echo "==> Initial settings"
    odoo_shell "${STACK}/initial.py"
else
    db_major="$(db version | cut -d. -f1-2)"
    image_major="$(odoo --version | sed -E 's/^Odoo Server ([0-9]+\.[0-9]+).*/\1/')"
    if [ "${db_major}" != "${image_major}" ]; then
        echo "Database is Odoo ${db_major}, image is ${image_major}: major upgrades need Odoo's upgrade process." >&2
        exit 1
    fi
    previous_image="$(db param docker_stack.image)"
    if [ "${previous_image}" != "${ODOO_VERSION}" ]; then
        echo "==> Updating modules for image ${ODOO_VERSION} (was: ${previous_image:-unknown})"
        odoo_cli -u all --stop-after-init
    fi
fi

missing="$(db missing "${ODOO_MODULES}")"
if [ -n "${missing}" ]; then
    echo "==> Installing modules: ${missing}"
    odoo_cli -i "${missing}" --stop-after-init
fi

echo "==> Applying environment (URL, reports)"
odoo_shell "${STACK}/environment.py"

echo "==> Done: Odoo ${ODOO_VERSION}, database ${ODOO_DB}"
echo "    URL:   ${ODOO_URL}"
echo "    Admin: ${ODOO_ADMIN_USER}"

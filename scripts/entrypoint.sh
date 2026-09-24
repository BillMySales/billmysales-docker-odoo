#!/bin/sh
# Odoo server entrypoint: configuration from the environment, then the
# official image's entrypoint (which waits for PostgreSQL).
set -eu
# shellcheck source=/dev/null
. /usr/local/share/stack/scripts/odoo-conf.sh
exec /entrypoint.sh "$@"

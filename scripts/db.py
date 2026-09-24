"""Small database helpers for setup.sh (psycopg2 ships with Odoo).

    python3 db.py installed        # prints 1 if the Odoo database is initialized
    python3 db.py version          # prints the installed `base` module version (e.g. 19.0.1.3)
    python3 db.py param <key>      # prints an ir.config_parameter value
    python3 db.py missing <mods>   # prints the given modules (comma separated) that aren't installed

Errors go to stderr with a non-zero exit code.
"""

import os
import sys

import psycopg2


def main() -> None:
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        connection = psycopg2.connect(
            host=os.environ["DB_HOST"], port=os.environ["DB_PORT"], user=os.environ["DB_USER"],
            password=os.environ["DB_PASSWORD"], dbname=os.environ["ODOO_DB"],
        )
    except psycopg2.OperationalError as error:
        if 'does not exist' in str(error) and command == "installed":
            return
        raise
    with connection, connection.cursor() as cursor:
        if command == "installed":
            cursor.execute("SELECT to_regclass('public.ir_module_module')")
            print("1" if cursor.fetchone()[0] else "", end="")
        elif command == "version":
            cursor.execute("SELECT latest_version FROM ir_module_module WHERE name = 'base'")
            print(cursor.fetchone()[0] or "", end="")
        elif command == "param":
            cursor.execute("SELECT value FROM ir_config_parameter WHERE key = %s", (sys.argv[2],))
            row = cursor.fetchone()
            print(row[0] if row else "", end="")
        elif command == "missing":
            wanted = [name for name in sys.argv[2].split(",") if name]
            cursor.execute("SELECT name FROM ir_module_module WHERE state = 'installed' AND name = ANY(%s)", (wanted,))
            installed = {row[0] for row in cursor.fetchall()}
            print(",".join(name for name in wanted if name not in installed), end="")
        else:
            raise SystemExit("Usage: db.py installed | version | param <key> | missing <modules>")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:  # noqa: BLE001 - report any failure to setup.sh
        print(f"db.py: {error}", file=sys.stderr)
        sys.exit(1)

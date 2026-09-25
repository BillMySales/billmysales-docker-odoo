Odoo Docker stack
=================

Docker Compose stack for [Odoo](https://www.odoo.com) Community (ERP: sales,
invoicing, inventory, ...), usable for local development and for simple
production deployments (a single server). Maintained by
[BillMySales](https://www.billmysales.com).

| Component   | Image                             | Default version     |
|-------------|-----------------------------------|---------------------|
| Web server  | `caddy:<ver>-alpine`              | 2.11                |
| Odoo        | `odoo:<ver>` (official)           | 19.0-20260908       |
| Database    | `postgres:<ver>-alpine`           | 18                  |
| Mailpit     | `axllent/mailpit` (optional, dev) | v1.31               |

All images are official (Docker Official Images, or the vendor's for Mailpit);
nothing is built locally. The Odoo image includes wkhtmltopdf for PDF reports.

Requirements
------------

- Docker Engine 24+ with the Compose v2 plugin (`docker compose`, 2.20+).
- About 3 GB of disk for the images; 2 GB of RAM or more for Odoo.
- Development: ports 8108, 8408 and 8025 free on the host.
- Production: a server with ports 80 and 443 reachable, and a DNS record for
  the site's domain pointing to it.

Quick start (development)
-------------------------

```shell
cp .env.dev.example .env
docker compose up -d
docker compose logs -f setup   # wait for "==> Done" (about 1 minute)
```

- Odoo: http://localhost:8108 (user `admin`, password `admin12345`)
- Mailpit (every email Odoo sends): http://localhost:8025

Production
----------

```shell
cp .env.prod.example .env
# Fill in ODOO_URL, SITE_ADDRESS, ODOO_MASTER_PASSWORD, DB_PASSWORD,
# ODOO_ADMIN_PASSWORD, ODOO_ADMIN_EMAIL and the SMTP_* values.
docker compose up -d
```

- With `SITE_ADDRESS` set to the domain, Caddy gets a Let's Encrypt certificate
  and renews it automatically (certificates live in the `caddy_data` volume).
- Behind another TLS-terminating proxy, use `SITE_ADDRESS=:80`; Odoo runs with
  `proxy_mode`, so the proxy's `X-Forwarded-*` headers give it the scheme,
  host and client IP.
- Compose refuses to start while a required value is missing.
- Configure SMTP: without it Odoo can't send any mail (quotations, invoices,
  password resets).
- The `backup` profile is enabled by default in the production template.
- Behind an existing Traefik (no host ports), use `overrides/traefik.yaml`
  (see [Overrides](#overrides)).

Services
--------

| Service   | Profile   | Role                                                              |
|-----------|-----------|-------------------------------------------------------------------|
| `db`      |           | PostgreSQL, data in the `db_data` volume.                         |
| `odoo`    |           | Odoo server (internal): HTTP workers, live updates, cron worker.  |
| `caddy`   |           | Web server and TLS, the only published ports (80, 443).           |
| `setup`   |           | One-shot job (`scripts/setup.sh`), runs on every `up`.            |
| `backup`  | `backup`  | Database dump + filestore archive on a schedule.                  |
| `mailpit` | `mailpit` | Development SMTP server that catches all mail.                    |
| `console` | `tools`   | Odoo shell and CLI, not started by `up`.                          |

Optional services are enabled with `COMPOSE_PROFILES` in `.env`, e.g.
`COMPOSE_PROFILES=backup`.

Odoo runs in multi-process mode (`ODOO_WORKERS`, default 2): HTTP requests on
port 8069, live updates (`/websocket`) on the gevent worker (8072) and
scheduled actions on a cron worker. Caddy routes both ports; the Odoo
configuration file is generated from the environment when each container
starts (`scripts/odoo-conf.sh`), so no secret is stored in the repository.

### What `setup` does

- Empty database: creates it with the `base` module and the `ODOO_LANG`
  language, without demo data. Then, only once: company name, country
  (`ODOO_COUNTRY`) and currency (`ODOO_CURRENCY`); admin login, password,
  email, language and time zone (`ODOO_TIMEZONE`). It stores the parameter
  `docker_stack.initialized`, so later changes made in Odoo are kept.
- Installs the `ODOO_MODULES` that aren't installed yet, on every run (so
  modules added to the list later are installed too). `account` with country
  CL also installs the Chilean localization (`l10n_cl`).
- New image (`ODOO_VERSION` changed within the same major version): updates
  every module (`-u all`). A new major version (e.g. 19 to 20) is refused:
  that needs Odoo's upgrade process, which this stack doesn't do.
- On every run: the public URL (`web.base.url`, frozen so it doesn't follow
  the browser's host) and the internal URL used to render PDF reports.

Common commands
---------------

```shell
docker compose ps                        # status: every service "healthy", setup "Exited (0)"
docker compose logs -f odoo              # Odoo logs
docker compose run --rm console shell    # Odoo shell (Python, `env` ready)
docker compose run --rm console module install stock   # install a module
docker compose exec db psql -U odoo odoo # SQL shell
docker compose down                      # stop, keep data
docker compose down -v                   # stop and DELETE all data
```

Modules can also be installed from Odoo's Apps menu as usual.

Point of sale
-------------

The Point of Sale app (`point_of_sale`) is not installed by default: a shop
needs its own setup (payment methods, cash control, products for sale).

1. Install it: add it to `ODOO_MODULES` (e.g.
   `ODOO_MODULES=sale_management,account,point_of_sale`) and run
   `docker compose up -d` (`setup` installs the missing modules), or install
   it from the Apps menu.
2. Open the Point of Sale app and choose a shop type (e.g. retail) without
   demo data: Odoo creates the point of sale in the company's currency (CLP)
   with the payment methods Cash, Card and Customer account.
3. Mark the products to sell as "Available in POS" (product form), then
   open a session from the point of sale's card.

Backups
-------

With the `backup` profile, the `backup` service writes `<timestamp>-db.dump`
(`pg_dump` custom format) and `<timestamp>-filestore.tar.gz` (attachments) to
the `backups` volume (or `./data/backups` with `overrides/local-dirs.yaml`) at
start and then every `BACKUP_INTERVAL_HOURS`, and deletes files older than
`BACKUP_KEEP_DAYS`. Files are readable by their owner only.

```shell
docker compose run --rm --no-deps backup now                  # back up now
docker compose run --rm --no-deps backup list                 # list timestamps
docker compose run --rm --no-deps backup restore <timestamp>  # restore database and filestore
docker compose restart odoo
```

`--no-deps` keeps the command from starting `setup` first (with damaged
data `setup` fails and the restore would never run); the database must
be running (`docker compose up -d db` if the stack is down).

A restore replaces the database with a fresh copy (`dropdb --force`,
`createdb`, `pg_restore`, closing Odoo's open connections), so nothing created
after the backup remains; `pg_restore --clean` would keep tables created
after the backup and block on Odoo's connections.

Overrides
---------

Optional compose files in `overrides/`, enabled with `COMPOSE_FILE` in `.env`
(several are combined with `:`). Each file documents its variables.

```shell
COMPOSE_FILE=compose.yaml:overrides/traefik.yaml:overrides/local-dirs.yaml
```

| File                        | Purpose                                                            |
|-----------------------------|--------------------------------------------------------------------|
| `overrides/traefik.yaml`    | Publish through an existing Traefik on a shared external network:  |
|                             | no host ports, Traefik terminates TLS (`TRAEFIK_HOST`, ...).       |
| `overrides/local-dirs.yaml` | Database, Odoo data, addons, Caddy and backups in local            |
|                             | directories (`DATA_DIR`, default `./data`) instead of volumes.     |
| `overrides/addon.yaml`      | Mount an addon from a local directory with auto-reload             |
|                             | (`ADDON_PATH`, `ADDON_NAME`; development only).                    |

A local `compose.override.yaml` (gitignored) is also loaded automatically by
Docker Compose, for changes specific to one machine.

Configuration
-------------

Every variable is documented in `.env.prod.example`. Main groups:

- **Site and network**: `ODOO_URL`, `SITE_ADDRESS`, `HTTP_BIND`, `HTTP_PORT`,
  `HTTPS_PORT`.
- **Credentials**: `ODOO_MASTER_PASSWORD`, `DB_PASSWORD`,
  `ODOO_ADMIN_PASSWORD`, `ODOO_ADMIN_EMAIL` (required).
- **Company and modules** (first install only, except modules):
  `ODOO_COMPANY_NAME`, `ODOO_LANG`, `ODOO_COUNTRY`, `ODOO_CURRENCY`,
  `ODOO_TIMEZONE`, `ODOO_MODULES`.
- **Versions**: `ODOO_VERSION`, `POSTGRES_VERSION`, `CADDY_VERSION`, ...
- **Odoo server**: `ODOO_WORKERS`, `ODOO_CRON_THREADS`, `ODOO_LIMIT_*`,
  `ODOO_LOG_LEVEL`, `ODOO_DEV`, `UPLOAD_MAX_SIZE` (Caddy).
- **Mail**: `SMTP_HOST`, `SMTP_PORT`, `SMTP_SECURE`, `SMTP_USER`,
  `SMTP_PASSWORD`, `SMTP_FROM`.
- **Resources and logs**: `*_MEMORY_LIMIT` per service, `LOG_MAX_SIZE`,
  `LOG_MAX_FILE` (Docker log rotation).

Notes:

- The SMTP settings configure Odoo's default mail server, which supports
  STARTTLS (`SMTP_SECURE=tls`, port 587) but not SMTPS (port 465); for that,
  add a server in Settings > Technical > Outgoing Mail Servers (such servers
  take precedence over the default one).
- Odoo 19 is served in the `es_CL` language by default; users choose their own
  language in their preferences. More languages: Settings > Languages.
- The site URL comes from `ODOO_URL`: changing the domain or port only needs
  `docker compose up -d`.
- Extra addons go in the `addons` volume (`/mnt/extra-addons`, one directory
  per addon), or are mounted with `overrides/addon.yaml`; restart `odoo`
  after adding one and install it from Apps or `ODOO_MODULES`. Odoo rejects
  `license: MIT` in an addon's manifest (use e.g. `LGPL-3` or `OPL-1`).
- `ODOO_LIMIT_MEMORY_*` limit each worker's virtual memory (Odoo's defaults,
  2 and 2.5 GiB); the real memory cap is the container's `ODOO_MEMORY_LIMIT`.
  Lower values from old guides (640/768 MiB) make workers respawn in a loop
  with `ODOO_DEV=reload`.
- `http_interface = 0.0.0.0` is set explicitly: Odoo 20 changes the default
  to `127.0.0.1`, which Caddy couldn't reach.
- In development mode (`overrides/addon.yaml`), Python 3.12 logs a
  `DeprecationWarning` about `fork()` when Odoo reloads: harmless.
- From inside the containers, the host machine is reachable as
  `host.docker.internal`.

Security
--------

- No default secrets: compose fails if the required passwords are missing. The
  development template uses public passwords; never use it on a server.
- One database only (`dbfilter`), the database manager disabled
  (`list_db = False`) and its pages blocked in Caddy (`/web/database/*`, `403`).
- `X-Content-Type-Options`, `X-Frame-Options` and `Referrer-Policy` headers;
  Odoo gets the real client IP (for its logs and login rate limiting) also
  behind Traefik.
- Only Caddy (and Mailpit in development) publishes ports; Odoo and the
  database are internal. `HTTP_BIND` defaults to `127.0.0.1`.
- Not included: a web application firewall or off-site backup copies.

Validation
----------

What was checked for this stack (2026-09-24):

- Clean start (`down -v` + `up -d`) in about 50 s: every service `healthy`,
  `setup` `Exited (0)`; a second run makes no changes.
- Login and backend (Sales) with all their CSS/JS (`200`), live updates over
  `/websocket` (`101`); database manager `403`; XML-RPC `version` and
  `authenticate`.
- Company in Chile with CLP (no decimals, `$` before), `l10n_cl` installed,
  admin in `es_CL` and `America/Santiago`.
- Mail through SMTP to Mailpit; the cron worker runs scheduled actions.
- Changes made in Odoo (company name, admin time zone) survive `setup`;
  `ODOO_URL` change; module update on a new image and refusal of a new major
  version; backup and restore (including data created after the backup).
- HTTPS with `SITE_ADDRESS=localhost` (Caddy internal CA, HTTP/2, websocket).
- Overrides: Traefik v3.6 routing with no host ports (HTTPS, websocket, real
  client IP), local directories (including backups), an addon mounted with
  auto-reload.
- Not tested: issuing a real Let's Encrypt certificate (needs a public domain).

Resource usage
--------------

Idle, after a few requests: Caddy ~11 MiB, Odoo ~275 MiB (2 HTTP workers,
gevent and cron; grows with use), PostgreSQL ~110 MiB.

License
-------

[MIT](LICENSE).

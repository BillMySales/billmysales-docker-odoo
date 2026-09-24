# Settings that follow the environment, run by setup.sh through `odoo shell`
# on every `docker compose up`.
import os

params = env["ir.config_parameter"]
wanted = {
    # Public URL, frozen so a request through another host doesn't change it.
    "web.base.url": os.environ["ODOO_URL"].rstrip("/"),
    "web.base.url.freeze": "True",
    # PDF reports (wkhtmltopdf) fetch their styles from Odoo itself, not
    # through the public URL (not reachable from inside the container).
    "report.url": "http://127.0.0.1:8069",
    "docker_stack.image": os.environ["ODOO_VERSION"],
}
for key, value in wanted.items():
    if params.get_param(key) != value:
        params.set_param(key, value)
        print(f"    {key} updated")
env.cr.commit()

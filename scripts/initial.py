# Initial settings, run once by setup.sh through `odoo shell` (`env` is the
# Odoo environment). Company in Chile with CLP, admin user from the
# environment. Runs before installing ODOO_MODULES, so installing `account`
# picks the country's localization (l10n_cl).
import os

from odoo import fields

country = env["res.country"].search([("code", "=", os.environ["ODOO_COUNTRY"].upper())], limit=1)
currency = env["res.currency"].with_context(active_test=False).search(
    [("name", "=", os.environ["ODOO_CURRENCY"].upper())], limit=1)
currency.active = True

company = env.ref("base.main_company")
company.write({
    "name": os.environ["ODOO_COMPANY_NAME"],
    "country_id": country.id,
    "currency_id": currency.id,
})

lang = os.environ["ODOO_LANG"]
admin = env.ref("base.user_admin")
admin.write({
    "login": os.environ["ODOO_ADMIN_USER"],
    "password": os.environ["ODOO_ADMIN_PASSWORD"],
    "email": os.environ["ODOO_ADMIN_EMAIL"],
    "lang": lang,
    "tz": os.environ["ODOO_TIMEZONE"],
})
admin.partner_id.write({"email": os.environ["ODOO_ADMIN_EMAIL"], "lang": lang})
env["ir.default"].set("res.partner", "lang", lang)
env["ir.config_parameter"].set_param("docker_stack.initialized", fields.Datetime.now().isoformat())
env.cr.commit()
print(f"    company: {company.name} ({country.code}, {currency.name}); admin: {admin.login}")

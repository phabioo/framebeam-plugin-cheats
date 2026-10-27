-- Entry module of the Cheats plugin.
local controller = require("app.controller")

fb.log.info(fb.i18n.t("loaded", { version = (fb.plugin and fb.plugin.version) or "?" }))
local app = controller.new(fb)
app:start()

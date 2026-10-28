-- Entry module of the Cheats plugin.
local controller = require("app.controller")

uz.log.info(uz.i18n.t("loaded", { version = (uz.plugin and uz.plugin.version) or "?" }))
local app = controller.new(uz)
app:start()

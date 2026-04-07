local Driver = require "st.driver"

local constants = require "constants"
local command_handlers = require "command_handlers"
local discovery = require "discovery"
local lifecycle_handlers = require "lifecycle_handlers"

local kocom_driver = Driver(constants.DRIVER_NAME, {
  discovery = discovery.discovery_handler,
  lifecycle_handlers = {
    added = lifecycle_handlers.added,
    init = lifecycle_handlers.init,
    removed = lifecycle_handlers.removed,
    infoChanged = lifecycle_handlers.info_changed,
  },
  capability_handlers = command_handlers.capability_handlers(),
})

kocom_driver:run()

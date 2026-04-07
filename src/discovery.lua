local log = require "log"

local constants = require "constants"

local discovery = {}

local function next_parent_index(driver)
  local max_index = 0
  for _, device in ipairs(driver:get_devices()) do
    local value = tostring(device.device_network_id or "")
    local idx = tonumber(value:match("kocom%-gateway%-(%d+)$"))
    if idx ~= nil and idx > max_index then
      max_index = idx
    end
  end
  return max_index + 1
end

function discovery.discovery_handler(driver, _, should_continue)
  local has_unconfigured_parent = false

  for _, device in ipairs(driver:get_devices()) do
    if device.parent_device_id == nil then
      local host = device.preferences and device.preferences.host
      if host == nil or tostring(host):match("^%s*$") then
        has_unconfigured_parent = true
        break
      end
    end
  end

  if has_unconfigured_parent then
    log.info_with({ hub_logs = true }, "Skipping parent creation because an unconfigured gateway already exists")
    return
  end

  if not should_continue() then
    return
  end

  local index = next_parent_index(driver)
  local metadata = {
    type = "LAN",
    device_network_id = string.format("kocom-gateway-%d", index),
    label = string.format("Kocom Gateway %d", index),
    profile = constants.PARENT_PROFILE,
    manufacturer = "KOCOM",
    model = "RS485 Gateway",
    vendor_provided_label = string.format("Kocom Gateway %d", index),
  }

  log.info_with({ hub_logs = true }, string.format("Creating Kocom gateway placeholder %s", metadata.device_network_id))
  driver:try_create_device(metadata)
end

return discovery

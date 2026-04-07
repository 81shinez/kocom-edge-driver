local constants = require "constants"

local mappings = {}

local code_to_device = {}
for device_type, code in pairs(constants.DEVICE_CODE_DEFAULTS) do
  code_to_device[code] = device_type
end

local function parse_numeric_code(value)
  if type(value) == "number" then
    return math.floor(value)
  end

  if type(value) == "string" then
    local trimmed = value:match("^%s*(.-)%s*$")
    if trimmed:sub(1, 2):lower() == "0x" then
      return tonumber(trimmed:sub(3), 16)
    end
    return tonumber(trimmed)
  end
end

function mappings.device_code_for(config, device_type)
  local override = config and config.device_code_overrides and config.device_code_overrides[device_type]
  local parsed = parse_numeric_code(override)
  if parsed ~= nil then
    return parsed
  end
  return constants.DEVICE_CODE_DEFAULTS[device_type]
end

function mappings.device_type_for_code(config, code)
  if config and config.device_code_overrides then
    for device_type, _ in pairs(constants.DEVICE_CODE_DEFAULTS) do
      if mappings.device_code_for(config, device_type) == code then
        return device_type
      end
    end
  end
  return code_to_device[code]
end

function mappings.profile_for_device_type(device_type)
  return constants.PROFILES[device_type]
end

function mappings.override_for_action(config, child_key, device_type, action)
  local overrides = config and config.command_overrides or {}
  local exact = overrides[child_key]
  if type(exact) == "table" and type(exact[action]) == "table" then
    return exact[action]
  end

  local by_type = overrides[device_type]
  if type(by_type) == "table" and type(by_type[action]) == "table" then
    return by_type[action]
  end

  return nil
end

return mappings

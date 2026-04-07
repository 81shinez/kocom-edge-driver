local json = require "st.json"
local log = require "log"

local constants = require "constants"

local preferences = {}

local function parse_json_string(raw, fallback)
  if raw == nil or raw == "" then
    return fallback
  end

  local ok, decoded = pcall(json.decode, raw)
  if not ok or type(decoded) ~= "table" then
    return fallback, "invalid json"
  end
  return decoded
end

local function normalize_port(value)
  if value == nil or value == 0 then
    return constants.DEFAULT_PORT
  end
  local num = tonumber(value)
  if num == nil then
    return constants.DEFAULT_PORT
  end
  num = math.floor(num)
  if num < 1 or num > 65535 then
    return constants.DEFAULT_PORT
  end
  return num
end

function preferences.build_parent_config(device)
  local pref = device.preferences or {}
  local host = tostring(pref.host or ""):match("^%s*(.-)%s*$")
  local protocol_preset = pref.protocolPreset or "kocom-default"

  local device_code_overrides, device_code_error = parse_json_string(pref.deviceCodeOverrides, {})
  local command_overrides, command_override_error = parse_json_string(pref.commandOverrides, {})

  if device_code_error then
    log.warn(string.format("[%s] invalid deviceCodeOverrides json", device.id))
  end
  if command_override_error then
    log.warn(string.format("[%s] invalid commandOverrides json", device.id))
  end

  local config = {
    host = host,
    port = normalize_port(pref.port),
    protocol_preset = protocol_preset,
    device_code_overrides = device_code_overrides,
    command_overrides = command_overrides,
    debug_unknown_frames = pref.debugUnknownFrames == true,
    capture_special_frames = pref.captureSpecialFrames == true,
  }

  config.is_configured = config.host ~= nil and config.host ~= ""
  return config
end

return preferences

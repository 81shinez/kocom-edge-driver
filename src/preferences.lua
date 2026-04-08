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

local function decode_packet_hex(packet_hex)
  if type(packet_hex) ~= "string" then
    return nil, "packetHex must be string"
  end

  local hex = packet_hex:gsub("%s+", "")
  if hex == "" then
    return nil, "packetHex is empty"
  end
  if #hex % 2 ~= 0 then
    return nil, "packetHex must have even length"
  end

  local bytes = {}
  for index = 1, #hex, 2 do
    local value = tonumber(hex:sub(index, index + 1), 16)
    if value == nil then
      return nil, "packetHex contains non-hex characters"
    end
    bytes[#bytes + 1] = string.char(value)
  end
  return table.concat(bytes)
end

local function compile_command_overrides(device_id, command_overrides)
  local compiled = {}

  for override_target, action_map in pairs(command_overrides or {}) do
    if type(action_map) ~= "table" then
      log.warn(string.format("[%s] invalid commandOverrides target %s: expected object", device_id, tostring(override_target)))
    else
      for action, override in pairs(action_map) do
        if type(override) ~= "table" then
          log.warn(string.format("[%s] invalid commandOverrides entry %s.%s: expected object", device_id, tostring(override_target), tostring(action)))
        else
          local packet, packet_err = decode_packet_hex(override.packetHex)
          if packet == nil then
            log.warn(string.format(
              "[%s] invalid commandOverrides packet for %s.%s (%s)",
              device_id,
              tostring(override_target),
              tostring(action),
              packet_err or "unknown"
            ))
          else
            local timeout_ms = tonumber(override.timeoutMs)
            local timeout_sec = timeout_ms and math.max(timeout_ms / 1000, 0) or 0

            compiled[override_target] = compiled[override_target] or {}
            compiled[override_target][action] = {
              packet = packet,
              timeout_sec = timeout_sec,
            }
          end
        end
      end
    end
  end

  return compiled
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
    command_overrides_compiled = compile_command_overrides(device.id, command_overrides),
    debug_unknown_frames = pref.debugUnknownFrames == true,
    capture_special_frames = pref.captureSpecialFrames == true,
  }

  config.is_configured = config.host ~= nil and config.host ~= ""
  return config
end

return preferences

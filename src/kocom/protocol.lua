local log = require "log"

local constants = require "constants"
local mappings = require "kocom.mappings"

local protocol = {}

local function rshift4(value)
  return math.floor((value or 0) / 16)
end

local function low_nibble(value)
  return (value or 0) % 16
end

local function bytes_to_hex(raw)
  return (raw:gsub(".", function(char)
    return string.format("%02X", string.byte(char))
  end))
end

local function build_key(device_type, room_index, device_index, sub_type)
  return string.format("%s-%d-%d-%s", device_type, room_index or 0, device_index or 0, sub_type or constants.SUB_TYPES.none)
end

local function byte_array_from_string(raw)
  local bytes = {}
  for index = 1, #raw do
    bytes[index] = string.byte(raw, index)
  end
  return bytes
end

local function packet_checksum(body_bytes)
  local sum = 0
  for _, value in ipairs(body_bytes) do
    sum = (sum + value) % 256
  end
  return sum
end

local function bytes_to_string(bytes)
  local chars = {}
  for _, byte in ipairs(bytes) do
    table.insert(chars, string.char(byte))
  end
  return table.concat(chars)
end

local function build_packet(body_bytes)
  local packet = { 0xAA, 0x55 }
  for _, value in ipairs(body_bytes) do
    table.insert(packet, value)
  end
  table.insert(packet, packet_checksum(body_bytes))
  table.insert(packet, 0x0D)
  table.insert(packet, 0x0D)
  return bytes_to_string(packet)
end

local function room_device_label(device_type, room_index, device_index)
  local label = constants.LABELS[device_type] or device_type
  return string.format("%s %d-%d", label, room_index, device_index + 1)
end

local function make_update(device_type, room_index, device_index, value, profile, packet_hex)
  return {
    key = build_key(device_type, room_index, device_index, constants.SUB_TYPES.none),
    device_type = device_type,
    room_index = room_index,
    device_index = device_index,
    sub_type = constants.SUB_TYPES.none,
    profile = profile or mappings.profile_for_device_type(device_type),
    label = room_device_label(device_type, room_index, device_index),
    value = value,
    packet_hex = packet_hex,
  }
end

local function parse_floor(frame)
  local first = frame.payload[2]
  local second = frame.payload[3]
  if first == 0 then
    return "unknown"
  end
  if second ~= 0 then
    return string.char(first) .. string.char(second)
  end
  if rshift4(first) == 0x08 then
    return string.format("B%d", low_nibble(first))
  end
  return tostring(first)
end

local function packet_type(raw_bytes)
  return rshift4(raw_bytes[4])
end

local function resolve_peer(raw_bytes)
  local dest_dev = raw_bytes[6]
  local dest_room = raw_bytes[7]
  local src_dev = raw_bytes[8]
  local src_room = raw_bytes[9]

  if dest_dev == 0x01 then
    return src_dev, src_room
  end
  if src_dev == 0x01 then
    return dest_dev, dest_room
  end
  return nil, nil
end

local function parse_switch_like(frame, device_type, updates)
  if frame.command ~= 0x00 then
    return
  end
  for idx = 1, 8 do
    table.insert(updates, make_update(device_type, frame.room_index, idx - 1, frame.payload[idx] == 0xFF, mappings.profile_for_device_type(device_type), frame.packet_hex))
  end
end

local function parse_thermostat(frame, updates)
  if frame.command ~= 0x00 then
    return
  end

  local hvac_mode = rshift4(frame.payload[1]) == 0x01 and "heat" or "off"
  table.insert(updates, make_update(constants.DEVICE_TYPES.thermostat, frame.room_index, 0, {
    mode = hvac_mode,
    target_temp = frame.payload[3],
    current_temp = frame.payload[5],
    operating_state = hvac_mode == "heat" and "heating" or "idle",
    away = low_nibble(frame.payload[2]) == 0x01,
    error_code = frame.payload[7],
  }, constants.PROFILES.thermostat, frame.packet_hex))
end

local function parse_ventilation(frame, updates)
  if frame.command ~= 0x00 then
    return
  end

  local switch_state = rshift4(frame.payload[1]) == 0x01
  local speed_raw = frame.payload[3]
  local level = 0
  if speed_raw == 0x40 then
    level = 33
  elseif speed_raw == 0x80 then
    level = 66
  elseif speed_raw == 0xC0 then
    level = 100
  end

  table.insert(updates, make_update(constants.DEVICE_TYPES.ventilation, frame.room_index, 0, {
    switch = switch_state,
    level = level,
    speed_raw = speed_raw,
    preset = frame.payload[2],
    co2 = frame.payload[5] * 100 + frame.payload[6],
    error_code = frame.payload[7],
  }, constants.PROFILES.ventilation, frame.packet_hex))
end

local function parse_gas(frame, updates)
  if frame.command ~= 0x01 and frame.command ~= 0x02 then
    return
  end
  local valve = frame.command == 0x02 and "closed" or "unknown"
  table.insert(updates, make_update(constants.DEVICE_TYPES.gas, frame.room_index, 0, { valve = valve }, constants.PROFILES.gas, frame.packet_hex))
end

local function parse_elevator(frame, updates)
  local direction = "unknown"
  if frame.payload[1] == 0x00 and frame.packet_type == 0x0D then
    direction = "called"
  elseif frame.payload[1] == 0x00 then
    direction = "idle"
  elseif frame.payload[1] == 0x01 then
    direction = "downward"
  elseif frame.payload[1] == 0x02 then
    direction = "upward"
  elseif frame.payload[1] == 0x03 then
    direction = "arrival"
  end

  table.insert(updates, make_update(constants.DEVICE_TYPES.elevator, frame.room_index, 0, {
    direction = direction,
    floor = parse_floor(frame),
    active = frame.payload[1] ~= 0x03,
  }, constants.PROFILES.elevator, frame.packet_hex))
end

local function parse_motion(frame, updates)
  if frame.command ~= 0x00 and frame.command ~= 0x04 then
    return
  end
  table.insert(updates, make_update(constants.DEVICE_TYPES.motion, frame.room_index, 0, frame.command == 0x04, constants.PROFILES.motion, frame.packet_hex))
end

local function parse_air_quality(frame, updates)
  if frame.command ~= 0x00 and frame.command ~= 0x3A then
    return
  end

  table.insert(updates, make_update(constants.DEVICE_TYPES.air_quality, frame.room_index, 0, {
    co2 = frame.payload[3] * 256 + frame.payload[4],
    temperature = frame.payload[7],
    humidity = frame.payload[8],
    pm10 = frame.payload[1],
    pm25 = frame.payload[2],
    voc = frame.payload[5] * 256 + frame.payload[6],
  }, constants.PROFILES.air_quality, frame.packet_hex))
end

function protocol.inspect_frame(raw, config)
  local raw_bytes = byte_array_from_string(raw)
  local peer_code, room_index = resolve_peer(raw_bytes)
  local frame = {
    raw = raw,
    packet_hex = bytes_to_hex(raw),
    packet_type = packet_type(raw_bytes),
    dest_device_code = raw_bytes[6],
    dest_room_index = raw_bytes[7],
    src_device_code = raw_bytes[8],
    src_room_index = raw_bytes[9],
    command = raw_bytes[10],
    payload = {
      raw_bytes[11], raw_bytes[12], raw_bytes[13], raw_bytes[14],
      raw_bytes[15], raw_bytes[16], raw_bytes[17], raw_bytes[18],
    },
    peer_code = peer_code,
    room_index = room_index,
  }

  if peer_code ~= nil then
    frame.device_type = mappings.device_type_for_code(config, peer_code)
  end

  return frame
end

function protocol.decode_frame(raw, config)
  local frame = protocol.inspect_frame(raw, config)
  local peer_code = frame.peer_code
  if peer_code == nil then
    return {}
  end

  local device_type = frame.device_type
  if device_type == nil then
    if config and config.debug_unknown_frames then
      log.debug(string.format("Unknown device code 0x%02X for frame %s", peer_code, bytes_to_hex(raw)))
    end
    return {}
  end

  local updates = {}
  if device_type == constants.DEVICE_TYPES.light or device_type == constants.DEVICE_TYPES.outlet then
    parse_switch_like(frame, device_type, updates)
  elseif device_type == constants.DEVICE_TYPES.thermostat then
    parse_thermostat(frame, updates)
  elseif device_type == constants.DEVICE_TYPES.ventilation then
    parse_ventilation(frame, updates)
  elseif device_type == constants.DEVICE_TYPES.gas then
    parse_gas(frame, updates)
  elseif device_type == constants.DEVICE_TYPES.elevator then
    parse_elevator(frame, updates)
  elseif device_type == constants.DEVICE_TYPES.motion then
    parse_motion(frame, updates)
  elseif device_type == constants.DEVICE_TYPES.air_quality then
    parse_air_quality(frame, updates)
  end

  return updates
end

local function parse_child_key(child_key)
  local device_type, room_index, device_index, sub_type = child_key:match("^([%w_]+)%-(%d+)%-(%d+)%-([%w_]+)$")
  if device_type == nil then
    return nil
  end
  return {
    device_type = device_type,
    room_index = tonumber(room_index),
    device_index = tonumber(device_index),
    sub_type = sub_type,
  }
end

local function normalize_level(level)
  if level <= 0 then
    return 0
  end
  if level <= 33 then
    return 33
  end
  if level <= 66 then
    return 66
  end
  return 100
end

local function build_base_body(device_code, room_index, command, payload)
  local body = { 0x30, 0xBC, 0x00, device_code, room_index, 0x01, 0x00, command }
  for index = 1, 8 do
    table.insert(body, payload[index] or 0x00)
  end
  return body
end

local function build_switch_packet(config, registry, parsed, action)
  local payload = {}
  for index = 0, 7 do
    local is_on = registry:get_switch_state(parsed.device_type, parsed.room_index, index)
    if index == parsed.device_index then
      is_on = action == "turn_on"
    elseif is_on == nil then
      return nil, nil, nil, string.format("missing cached sibling state for %s-%d-%d-none", parsed.device_type, parsed.room_index, index)
    end
    payload[index + 1] = is_on and 0xFF or 0x00
  end

  local body = build_base_body(mappings.device_code_for(config, parsed.device_type), parsed.room_index, 0x00, payload)
  return build_packet(body), function(update)
    return update.key == build_key(parsed.device_type, parsed.room_index, parsed.device_index, constants.SUB_TYPES.none) and update.value == (action == "turn_on")
  end, constants.CONFIRM_TIMEOUT_SEC
end

local function build_thermostat_packet(config, parsed, action, args)
  local payload = { 0, 0, 0, 0, 0, 0, 0, 0 }
  if action == "set_thermostat_mode" then
    payload[1] = args.mode == "heat" and 0x11 or 0x00
  elseif action == "set_heating_setpoint" then
    payload[1] = 0x11
    payload[3] = math.floor(tonumber(args.setpoint) or 0)
  else
    return nil, nil, nil, "unsupported thermostat action"
  end

  local body = build_base_body(mappings.device_code_for(config, parsed.device_type), parsed.room_index, 0x00, payload)
  local expected_key = build_key(parsed.device_type, parsed.room_index, parsed.device_index, constants.SUB_TYPES.none)
  local timeout = action == "set_heating_setpoint" and math.max(constants.CONFIRM_TIMEOUT_SEC, 1.5) or constants.CONFIRM_TIMEOUT_SEC
  local matcher = function(update)
    if update.key ~= expected_key or type(update.value) ~= "table" then
      return false
    end
    if action == "set_thermostat_mode" then
      return update.value.mode == args.mode
    end
    return update.value.target_temp == math.floor(tonumber(args.setpoint) or 0)
  end

  return build_packet(body), matcher, timeout
end

local function build_ventilation_packet(config, parsed, action, args)
  local payload = { 0, 0, 0, 0, 0, 0, 0, 0 }
  if action == "turn_on" then
    payload[1] = 0x11
  elseif action == "turn_off" then
    payload[1] = 0x00
  elseif action == "set_level" then
    local level = normalize_level(tonumber(args.level) or 0)
    payload[1] = level == 0 and 0x00 or 0x11
    payload[3] = constants.VENT_LEVELS[level] or 0x00
  else
    return nil, nil, nil, "unsupported ventilation action"
  end

  local body = build_base_body(mappings.device_code_for(config, parsed.device_type), parsed.room_index, 0x00, payload)
  local expected_key = build_key(parsed.device_type, parsed.room_index, parsed.device_index, constants.SUB_TYPES.none)
  local matcher = function(update)
    if update.key ~= expected_key or type(update.value) ~= "table" then
      return false
    end
    if action == "turn_on" then
      return update.value.switch == true
    elseif action == "turn_off" then
      return update.value.switch == false
    end
    return update.value.level == normalize_level(tonumber(args.level) or 0)
  end

  return build_packet(body), matcher, constants.CONFIRM_TIMEOUT_SEC
end

local function build_gas_packet(config, parsed, action)
  if action ~= "close" then
    return nil, nil, nil, "unsupported gas action"
  end
  local body = build_base_body(mappings.device_code_for(config, parsed.device_type), parsed.room_index, 0x02, { 0, 0, 0, 0, 0, 0, 0, 0 })
  local expected_key = build_key(parsed.device_type, parsed.room_index, parsed.device_index, constants.SUB_TYPES.none)
  local matcher = function(update)
    return update.key == expected_key and type(update.value) == "table" and update.value.valve == "closed"
  end
  return build_packet(body), matcher, math.max(constants.CONFIRM_TIMEOUT_SEC, 1.5)
end

local function build_elevator_packet(config, parsed)
  local body = build_base_body(mappings.device_code_for(config, parsed.device_type), parsed.room_index, 0x01, {
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  })
  local expected_key = build_key(parsed.device_type, parsed.room_index, parsed.device_index, constants.SUB_TYPES.none)
  local matcher = function(update)
    return update.key == expected_key
  end
  return build_packet(body), matcher, constants.CONFIRM_TIMEOUT_SEC
end

local function override_packet(override)
  local bytes = {}
  local hex = tostring(override.packetHex or "")
  hex = hex:gsub("%s+", "")
  if #hex % 2 ~= 0 or hex == "" then
    return nil
  end
  for idx = 1, #hex, 2 do
    table.insert(bytes, tonumber(hex:sub(idx, idx + 1), 16))
  end
  return bytes_to_string(bytes)
end

function protocol.build_command(config, registry, child_key, action, args)
  local parsed = parse_child_key(child_key)
  if parsed == nil then
    return nil, nil, nil, "invalid child key"
  end

  local override = mappings.override_for_action(config, child_key, parsed.device_type, action)
  if override ~= nil then
    local packet = override_packet(override)
    if packet ~= nil then
      local timeout_override = tonumber(override.timeoutMs)
      local seconds = timeout_override and math.max(timeout_override / 1000, 0) or 0
      return packet, nil, seconds
    end
  end

  if parsed.device_type == constants.DEVICE_TYPES.light or parsed.device_type == constants.DEVICE_TYPES.outlet then
    return build_switch_packet(config, registry, parsed, action)
  elseif parsed.device_type == constants.DEVICE_TYPES.thermostat then
    return build_thermostat_packet(config, parsed, action, args)
  elseif parsed.device_type == constants.DEVICE_TYPES.ventilation then
    return build_ventilation_packet(config, parsed, action, args)
  elseif parsed.device_type == constants.DEVICE_TYPES.gas then
    return build_gas_packet(config, parsed, action)
  elseif parsed.device_type == constants.DEVICE_TYPES.elevator then
    return build_elevator_packet(config, parsed)
  end

  return nil, nil, nil, "unsupported device type or override missing"
end

return protocol

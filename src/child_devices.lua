local log = require "log"

local constants = require "constants"

local child_devices = {}

local function split_key(value)
  local parts = {}
  for item in string.gmatch(value or "", "([^%-]+)") do
    table.insert(parts, item)
  end
  return parts
end

function child_devices.make_child_key(device_type, room_index, device_index, sub_type)
  return string.format("%s-%d-%d-%s", device_type, room_index or 0, device_index or 0, sub_type or constants.SUB_TYPES.none)
end

function child_devices.parse_child_key(key)
  local parts = split_key(key)
  if #parts ~= 4 then
    return nil
  end

  return {
    device_type = parts[1],
    room_index = tonumber(parts[2]) or 0,
    device_index = tonumber(parts[3]) or 0,
    sub_type = parts[4],
    key = key,
  }
end

function child_devices.profile_for_device_type(device_type)
  return constants.PROFILES[device_type]
end

function child_devices.default_label_for_key(parsed)
  local label = constants.LABELS[parsed.device_type] or parsed.device_type

  if parsed.device_type == constants.DEVICE_TYPES.doorbell then
    return label
  end
  if parsed.device_type == constants.DEVICE_TYPES.elevator then
    return label
  end
  if parsed.device_type == constants.DEVICE_TYPES.gas then
    return label
  end

  return string.format("%s %d-%d", label, parsed.room_index, parsed.device_index + 1)
end

function child_devices.find_child(parent_device, child_key)
  if parent_device == nil or child_key == nil then
    return nil
  end
  if parent_device.get_child_by_parent_assigned_key == nil then
    return nil
  end
  return parent_device:get_child_by_parent_assigned_key(child_key)
end

function child_devices.build_child_metadata(parent_device, parsed, profile_name)
  local label = child_devices.default_label_for_key(parsed)
  return {
    type = "EDGE_CHILD",
    parent_device_id = parent_device.id,
    parent_assigned_child_key = parsed.key,
    label = string.format("%s %s", parent_device.label or "Kocom", label),
    profile = profile_name,
    manufacturer = "KOCOM",
    model = parsed.device_type,
    vendor_provided_label = label,
  }
end

function child_devices.ensure_child(driver, parent_device, update)
  local existing = child_devices.find_child(parent_device, update.key)
  if existing ~= nil then
    return existing
  end

  local parsed = child_devices.parse_child_key(update.key)
  if parsed == nil then
    return nil
  end

  local profile_name = update.profile or child_devices.profile_for_device_type(parsed.device_type)
  if profile_name == nil then
    return nil
  end

  local metadata = child_devices.build_child_metadata(parent_device, parsed, profile_name)
  log.info_with({ hub_logs = true }, string.format("[%s] creating child %s (%s)", parent_device.id, metadata.label, parsed.key))
  driver:try_create_device(metadata)
  return nil
end

function child_devices.iter_children(driver, parent_device)
  local children = {}
  for _, device in ipairs(driver:get_devices()) do
    if device.parent_device_id == parent_device.id then
      table.insert(children, device)
    end
  end
  return children
end

function child_devices.ensure_override_children(driver, parent_device, config)
  local overrides = config.command_overrides or {}

  for override_key, _ in pairs(overrides) do
    local parsed = child_devices.parse_child_key(override_key)
    if parsed == nil and constants.PROFILES[override_key] ~= nil then
      parsed = {
        key = child_devices.make_child_key(override_key, 0, 0, constants.SUB_TYPES.none),
        device_type = override_key,
        room_index = 0,
        device_index = 0,
        sub_type = constants.SUB_TYPES.none,
      }
    end

    if parsed ~= nil and constants.PROFILES[parsed.device_type] ~= nil then
      local existing = child_devices.find_child(parent_device, parsed.key)
      if existing == nil then
        local metadata = child_devices.build_child_metadata(parent_device, parsed, constants.PROFILES[parsed.device_type])
        log.info_with({ hub_logs = true }, string.format("[%s] creating override-driven child %s", parent_device.id, parsed.key))
        driver:try_create_device(metadata)
      end
    end
  end
end

return child_devices

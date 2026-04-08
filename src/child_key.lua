local constants = require "constants"

local child_key = {}

function child_key.make(device_type, room_index, device_index, sub_type)
  return string.format(
    "%s-%d-%d-%s",
    device_type,
    room_index or 0,
    device_index or 0,
    sub_type or constants.SUB_TYPES.none
  )
end

function child_key.parse(key)
  if type(key) ~= "string" then
    return nil
  end

  local device_type, room_index, device_index, sub_type = key:match("^([%w_]+)%-(%d+)%-(%d+)%-([%w_]+)$")
  if device_type == nil then
    return nil
  end

  return {
    device_type = device_type,
    room_index = tonumber(room_index),
    device_index = tonumber(device_index),
    sub_type = sub_type,
    key = key,
  }
end

return child_key

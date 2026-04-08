local constants = require "constants"
local child_key = require "child_key"

local Registry = {}
Registry.__index = Registry

function Registry.new()
  return setmetatable({
    states = {},
  }, Registry)
end

function Registry:get(key)
  return self.states[key]
end

function Registry:set(update)
  self.states[update.key] = update
end

function Registry:get_switch_state(device_type, room_index, device_index)
  local key = child_key.make(device_type, room_index, device_index, constants.SUB_TYPES.none)
  local state = self.states[key]
  if state == nil then
    return nil
  end
  return state.value == true
end

return Registry

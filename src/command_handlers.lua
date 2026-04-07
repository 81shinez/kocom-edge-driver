local capabilities = require "st.capabilities"
local log = require "log"

local constants = require "constants"

local command_handlers = {}

local function get_session(driver, device)
  local parent_id = device.parent_device_id or device.id
  local sessions = driver.datastore.sessions or {}
  return sessions[parent_id]
end

local function enqueue_command(driver, device, action, args)
  local session = get_session(driver, device)
  if session == nil then
    log.warn(string.format("[%s] no active session for command %s", device.id, action))
    return
  end

  local child_key = device.parent_assigned_child_key or device:get_field(constants.FIELDS.child_key)
  if child_key == nil and device.parent_device_id ~= nil then
    log.warn(string.format("[%s] missing child key for command %s", device.id, action))
    return
  end

  session:enqueue_command({
    child_key = child_key,
    action = action,
    args = args or {},
    source_device_id = device.id,
  })
end

function command_handlers.handle_switch_on(driver, device)
  enqueue_command(driver, device, "turn_on")
end

function command_handlers.handle_switch_off(driver, device)
  enqueue_command(driver, device, "turn_off")
end

function command_handlers.handle_set_level(driver, device, command)
  local level = tonumber(command.args.level or command.args[1]) or 0
  enqueue_command(driver, device, "set_level", { level = level })
end

function command_handlers.handle_thermostat_mode(driver, device, command)
  local mode = command.args.mode or command.args.thermostatMode or command.args[1] or "off"
  enqueue_command(driver, device, "set_thermostat_mode", { mode = mode })
end

function command_handlers.handle_heating_setpoint(driver, device, command)
  local setpoint = command.args.setpoint or command.args.heatingSetpoint or command.args[1]
  enqueue_command(driver, device, "set_heating_setpoint", { setpoint = tonumber(setpoint) or 0 })
end

function command_handlers.handle_momentary_push(driver, device)
  enqueue_command(driver, device, "push")
end

function command_handlers.handle_close_only_valve(driver, device)
  enqueue_command(driver, device, "close")
end

function command_handlers.handle_refresh(driver, device)
  local session = get_session(driver, device)
  if session == nil then
    return
  end

  if device.parent_device_id == nil then
    session:enqueue_control({ type = "refresh" })
  else
    local child_key = device.parent_assigned_child_key or device:get_field(constants.FIELDS.child_key)
    session:replay_child(child_key)
  end
end

function command_handlers.capability_handlers()
  local close_only = capabilities[constants.CAPABILITIES.close_only_valve]

  local handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = command_handlers.handle_switch_on,
      [capabilities.switch.commands.off.NAME] = command_handlers.handle_switch_off,
    },
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = command_handlers.handle_set_level,
    },
    [capabilities.thermostatMode.ID] = {
      [capabilities.thermostatMode.commands.setThermostatMode.NAME] = command_handlers.handle_thermostat_mode,
    },
    [capabilities.thermostatHeatingSetpoint.ID] = {
      [capabilities.thermostatHeatingSetpoint.commands.setHeatingSetpoint.NAME] = command_handlers.handle_heating_setpoint,
    },
    [capabilities.momentary.ID] = {
      [capabilities.momentary.commands.push.NAME] = command_handlers.handle_momentary_push,
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = command_handlers.handle_refresh,
    },
  }

  if close_only ~= nil and close_only.commands ~= nil and close_only.commands.close ~= nil then
    handlers[close_only.ID] = {
      [close_only.commands.close.NAME] = command_handlers.handle_close_only_valve,
    }
  end

  return handlers
end

return command_handlers

local capabilities = require "st.capabilities"
local log = require "log"

local constants = require "constants"
local child_devices = require "child_devices"

local emitter = {}

local function safe_emit(device, event)
  if event == nil then
    return
  end
  local ok, err = pcall(device.emit_event, device, event)
  if not ok then
    log.warn(string.format("[%s] failed to emit event: %s", device.id, err))
  end
end

local function emit_switch(device, is_on)
  safe_emit(device, is_on and capabilities.switch.switch.on() or capabilities.switch.switch.off())
end

local function emit_contact(device, contact_value)
  if contact_value == "open" then
    safe_emit(device, capabilities.contactSensor.contact.open())
  elseif contact_value == "closed" then
    safe_emit(device, capabilities.contactSensor.contact.closed())
  end
end

local function emit_button(device)
  safe_emit(device, capabilities.button.numberOfButtons({ value = 1 }))
  safe_emit(device, capabilities.button.button.pushed({ state_change = true }))
end

function emitter.apply_state(device, update)
  if device == nil or update == nil then
    return
  end

  device:set_field(constants.FIELDS.last_update, update, { persist = true })
  device:set_field(constants.FIELDS.last_packet, update.packet_hex, { persist = true })

  if update.device_type == constants.DEVICE_TYPES.light or update.device_type == constants.DEVICE_TYPES.outlet then
    emit_switch(device, update.value == true)
    return
  end

  if update.device_type == constants.DEVICE_TYPES.motion then
    safe_emit(device, update.value and capabilities.motionSensor.motion.active() or capabilities.motionSensor.motion.inactive())
    return
  end

  if update.device_type == constants.DEVICE_TYPES.thermostat then
    safe_emit(device, capabilities.thermostatMode.thermostatMode(update.value.mode or "off"))
    safe_emit(device, capabilities.thermostatHeatingSetpoint.heatingSetpoint({ value = update.value.target_temp or 0, unit = "C" }))
    safe_emit(device, capabilities.temperatureMeasurement.temperature({ value = update.value.current_temp or 0, unit = "C" }))
    safe_emit(device, capabilities.thermostatOperatingState.thermostatOperatingState(update.value.operating_state or "idle"))
    return
  end

  if update.device_type == constants.DEVICE_TYPES.ventilation then
    emit_switch(device, update.value.switch == true)
    if update.value.level ~= nil then
      safe_emit(device, capabilities.switchLevel.level(update.value.level))
    end
    return
  end

  if update.device_type == constants.DEVICE_TYPES.air_quality then
    if update.value.co2 ~= nil then
      safe_emit(device, capabilities.carbonDioxideMeasurement.carbonDioxide({ value = update.value.co2, unit = "ppm" }))
    end
    if update.value.temperature ~= nil then
      safe_emit(device, capabilities.temperatureMeasurement.temperature({ value = update.value.temperature, unit = "C" }))
    end
    if update.value.humidity ~= nil then
      safe_emit(device, capabilities.relativeHumidityMeasurement.humidity(update.value.humidity))
    end
    return
  end

  if update.device_type == constants.DEVICE_TYPES.door then
    if update.value.contact ~= nil then
      emit_contact(device, update.value.contact)
    end
    return
  end

  if update.device_type == constants.DEVICE_TYPES.doorbell then
    emit_button(device)
    return
  end

  if update.device_type == constants.DEVICE_TYPES.elevator then
    local direction_cap = capabilities[constants.CAPABILITIES.elevator_direction]
    local floor_cap = capabilities[constants.CAPABILITIES.elevator_floor]
    if direction_cap and update.value.direction ~= nil then
      safe_emit(device, direction_cap.direction(update.value.direction))
    end
    if floor_cap and update.value.floor ~= nil then
      safe_emit(device, floor_cap.floor(update.value.floor))
    end
    return
  end

  if update.device_type == constants.DEVICE_TYPES.gas then
    local gas_cap = capabilities[constants.CAPABILITIES.close_only_valve]
    if gas_cap and update.value.valve ~= nil then
      safe_emit(device, gas_cap.valve(update.value.valve))
    end
  end
end

function emitter.replay_cached_state(driver, child_device)
  if child_device == nil or child_device.parent_device_id == nil then
    return
  end

  local sessions = driver.datastore.sessions or {}
  local session = sessions[child_device.parent_device_id]

  local key = child_device.parent_assigned_child_key or child_device:get_field(constants.FIELDS.child_key)
  if key == nil then
    return
  end

  local update
  if session ~= nil and session.registry ~= nil then
    update = session.registry:get(key)
  end
  if update == nil then
    update = child_device:get_field(constants.FIELDS.last_update)
  end
  if update ~= nil then
    emitter.apply_state(child_device, update)
  end
end

function emitter.apply_update(driver, parent_device, update)
  local child = child_devices.find_child(parent_device, update.key)
  if child == nil then
    return false
  end

  emitter.apply_state(child, update)
  return true
end

return emitter

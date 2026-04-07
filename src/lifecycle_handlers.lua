local log = require "log"

local constants = require "constants"
local emitter = require "emitter"
local preferences = require "preferences"
local child_devices = require "child_devices"
local Session = require "kocom.session"

local lifecycle_handlers = {}

local function ensure_driver_datastore(driver)
  driver.datastore.sessions = driver.datastore.sessions or {}
end

local function is_parent(device)
  return device.parent_device_id == nil
end

local function has_parent_session(driver, device)
  local sessions = driver.datastore.sessions or {}
  return sessions[device.id] ~= nil
end

local function schedule_parent_monitor(driver, device)
  if not is_parent(device) then
    return
  end

  device.thread:call_on_schedule(constants.MONITOR_INTERVAL_SEC, function()
    local session = driver.datastore.sessions and driver.datastore.sessions[device.id]
    if session ~= nil then
      session:enqueue_control({ type = "monitor" })
    end
  end, string.format("%s-monitor", device.id))
end

local function start_or_restart_parent_session(driver, device)
  ensure_driver_datastore(driver)
  local config = preferences.build_parent_config(device)
  device:set_field(constants.FIELDS.parent_config, config)

  local existing = driver.datastore.sessions[device.id]
  if existing ~= nil then
    existing:stop()
  end

  local session = Session.new(driver, device, config)
  driver.datastore.sessions[device.id] = session

  child_devices.ensure_override_children(driver, device, config)

  if config.is_configured then
    device:online()
    session:start()
  else
    log.info_with({ hub_logs = true }, string.format("[%s] parent is waiting for host/port preferences", device.id))
    device:offline()
  end
end

function lifecycle_handlers.added(driver, device)
  if is_parent(device) then
    device:set_field(constants.FIELDS.init_started, false)
    return
  end

  local key = device.parent_assigned_child_key
  if key ~= nil then
    device:set_field(constants.FIELDS.child_key, key, { persist = true })
    local parsed = child_devices.parse_child_key(key)
    if parsed ~= nil then
      device:set_field(constants.FIELDS.child_device_type, parsed.device_type, { persist = true })
    end
  end
end

function lifecycle_handlers.init(driver, device)
  ensure_driver_datastore(driver)

  local init_started = device:get_field(constants.FIELDS.init_started) == true
  if is_parent(device) and not has_parent_session(driver, device) then
    init_started = false
    device:set_field(constants.FIELDS.init_started, false)
  end

  if init_started then
    if not is_parent(device) then
      emitter.replay_cached_state(driver, device)
    end
    return
  end

  device:set_field(constants.FIELDS.init_started, true)

  if is_parent(device) then
    schedule_parent_monitor(driver, device)
    start_or_restart_parent_session(driver, device)
    return
  end

  emitter.replay_cached_state(driver, device)
end

function lifecycle_handlers.info_changed(driver, device, event, args)
  if not is_parent(device) then
    return
  end

  log.info_with({ hub_logs = true }, string.format("[%s] parent preferences changed", device.id))
  start_or_restart_parent_session(driver, device)
end

function lifecycle_handlers.removed(driver, device)
  if not is_parent(device) then
    return
  end

  local sessions = driver.datastore.sessions or {}
  local session = sessions[device.id]
  if session ~= nil then
    session:stop()
    sessions[device.id] = nil
  end
end

return lifecycle_handlers

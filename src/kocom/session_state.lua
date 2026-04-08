local child_devices = require "child_devices"
local constants = require "constants"
local transport = require "kocom.transport"

local session_state = {}

function session_state.mark_parent_online(session)
  if session.connected then
    return
  end

  session.connected = true
  session.parent_device:online()
  for _, child in ipairs(child_devices.iter_children(session.driver, session.parent_device)) do
    child:online()
  end
end

function session_state.mark_parent_offline(session, reason)
  session.connected = false
  session.parent_device:set_field(constants.FIELDS.last_error, reason, { persist = true })
  session.parent_device:offline()
  for _, child in ipairs(child_devices.iter_children(session.driver, session.parent_device)) do
    child:offline()
  end
end

function session_state.seed_registry_from_children(session)
  for _, child in ipairs(child_devices.iter_children(session.driver, session.parent_device)) do
    local update = child:get_field(constants.FIELDS.last_update)
    if type(update) == "table" and update.key ~= nil then
      session.registry:set(update)
    end
  end
end

function session_state.finalize_stop(session)
  local datastore = session.driver and session.driver.datastore
  local sessions = datastore and datastore.sessions
  local current_session = sessions and sessions[session.parent_device.id]

  if current_session == session then
    session:_disconnect("stopped")
  else
    session.connected = false
    if session.sock ~= nil then
      transport.close(session.sock)
      session.sock = nil
    end
  end

  if session.command_rx ~= nil then
    pcall(session.command_rx.close, session.command_rx)
  end
end

return session_state

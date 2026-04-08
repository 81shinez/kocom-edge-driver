local log = require "log"

local child_devices = require "child_devices"
local constants = require "constants"
local emitter = require "emitter"
local parser = require "kocom.parser"
local protocol = require "kocom.protocol"
local session_connection = require "kocom.session_connection"

local session_frames = {}

function session_frames.log_special_frame(session, frame)
  if frame == nil then
    return
  end

  local extras = {}
  if frame.peer_code ~= nil then
    table.insert(extras, string.format("peer=0x%02X", frame.peer_code))
  end
  if frame.room_index ~= nil then
    table.insert(extras, string.format("room=%d", frame.room_index))
  end
  if frame.device_type ~= nil then
    table.insert(extras, string.format("device_type=%s", frame.device_type))
  elseif frame.room_index ~= nil then
    table.insert(extras, string.format(
      "child_key_hints=%s,%s",
      child_devices.make_child_key(constants.DEVICE_TYPES.door, frame.room_index, 0, constants.SUB_TYPES.none),
      child_devices.make_child_key(constants.DEVICE_TYPES.doorbell, frame.room_index, 0, constants.SUB_TYPES.none)
    ))
  end

  log.info_with(
    { hub_logs = true },
    string.format(
      "[%s] captured frame raw=%s packet_type=0x%X command=0x%02X%s",
      session.parent_device.id,
      frame.packet_hex,
      frame.packet_type or 0,
      frame.command or 0,
      #extras > 0 and (" " .. table.concat(extras, " ")) or ""
    )
  )
end

function session_frames.handle_updates(session, updates)
  for _, update in ipairs(updates) do
    session.registry:set(update)
    child_devices.ensure_child(session.driver, session.parent_device, update)
    if session.active_matcher ~= nil and session.active_matcher(update) then
      session.active_match_hit = true
    end
    emitter.apply_update(session.driver, session.parent_device, update)
  end
end

function session_frames.handle_frame(session, frame)
  local frame_info
  if session.config.capture_special_frames then
    frame_info = protocol.inspect_frame(frame, session.config)
  end

  local updates = protocol.decode_frame(frame, session.config)
  if #updates == 0 then
    if session.config.debug_unknown_frames then
      log.debug(string.format("[%s] no logical update for frame", session.parent_device.id))
    end
    if session.config.capture_special_frames then
      session:_log_special_frame(frame_info)
    end
  end
  session:_handle_updates(updates)
end

function session_frames.read_available(session)
  if session.sock == nil then
    return false
  end

  local data, err, partial = session.sock:receive(constants.READ_SIZE)
  local chunk = data or partial
  if chunk ~= nil and chunk ~= "" then
    session.last_activity = session_connection.monotonic()
    for _, frame in ipairs(session.parser:feed(chunk)) do
      local ok, reason = parser.validate_frame(frame)
      if ok then
        session:_handle_frame(frame)
      elseif session.config.debug_unknown_frames then
        log.debug(string.format("[%s] invalid frame dropped: %s", session.parent_device.id, reason))
      end
    end
    return true
  end

  if err ~= nil and err ~= "timeout" then
    log.warn(string.format("[%s] receive error: %s", session.parent_device.id, err))
    session:_disconnect(err)
    return false
  end
  return true
end

return session_frames

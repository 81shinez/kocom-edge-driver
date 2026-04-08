local socket = require "cosock.socket"
local log = require "log"

local constants = require "constants"
local protocol = require "kocom.protocol"
local session_connection = require "kocom.session_connection"

local session_commands = {}

function session_commands.wait_for_match(session, timeout_sec)
  local deadline = session_connection.monotonic() + timeout_sec
  while session.running and session.sock ~= nil and session_connection.monotonic() < deadline do
    local recvt, _, err = socket.select({ session.sock }, nil, constants.RECV_TIMEOUT)
    if err ~= nil and err ~= "timeout" then
      session:_disconnect(err)
      return false
    end
    if recvt and (recvt[1] == session.sock or recvt[2] == session.sock) then
      session:_read_available()
      if session.active_match_hit then
        return true
      end
    end
  end
  return session.active_match_hit
end

function session_commands.process_command(session, command)
  if session.sock == nil and not session:_connect() then
    return
  end

  local packet, matcher, timeout_sec, err = protocol.build_command(
    session.config,
    session.registry,
    command.child_key,
    command.action,
    command.args or {}
  )
  if packet == nil then
    log.warn(string.format(
      "[%s] unable to build command %s for %s: %s",
      session.parent_device.id,
      command.action,
      tostring(command.child_key),
      err or "unknown"
    ))
    return
  end

  local effective_timeout = timeout_sec or 0
  for attempt = 1, constants.SEND_RETRY_MAX do
    if session.sock == nil and not session:_connect() then
      return
    end

    if not session:_send_packet(packet) then
      if attempt < constants.SEND_RETRY_MAX then
        session:_sleep_for_backoff()
      end
    else
      if matcher == nil or effective_timeout <= 0 then
        return
      end

      session.active_matcher = matcher
      session.active_match_hit = false
      if session:_wait_for_match(effective_timeout) then
        session.active_matcher = nil
        session.active_match_hit = false
        return
      end
      session.active_matcher = nil
      session.active_match_hit = false
    end

    socket.sleep(constants.SEND_RETRY_GAP_SEC)
  end

  log.warn(string.format(
    "[%s] command %s did not confirm for %s",
    session.parent_device.id,
    command.action,
    command.child_key
  ))
end

return session_commands

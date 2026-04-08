local socket = require "cosock.socket"
local log = require "log"

local constants = require "constants"
local transport = require "kocom.transport"

local session_connection = {}

function session_connection.monotonic()
  return socket.gettime()
end

function session_connection.connect(session)
  if not session.config.is_configured then
    return false
  end

  local sock, err = transport.connect(session.config.host, session.config.port)
  if sock == nil then
    session:mark_parent_offline(err or "connect_failed")
    log.warn(string.format(
      "[%s] failed to connect %s:%s (%s)",
      session.parent_device.id,
      session.config.host,
      session.config.port,
      err or "unknown"
    ))
    return false
  end

  session.sock = sock
  session.last_activity = session_connection.monotonic()
  session.backoff = constants.RECONNECT_MIN_SEC
  session:mark_parent_online()
  log.info_with(
    { hub_logs = true },
    string.format("[%s] connected to %s:%s", session.parent_device.id, session.config.host, session.config.port)
  )
  return true
end

function session_connection.disconnect(session, reason)
  if session.sock ~= nil then
    transport.close(session.sock)
    session.sock = nil
  end
  session:mark_parent_offline(reason or "disconnected")
end

function session_connection.sleep_for_backoff(session)
  local delay = session.backoff
  session.backoff = math.min(session.backoff * 2, constants.RECONNECT_MAX_SEC)
  socket.sleep(delay)
end

function session_connection.ensure_idle_gap(session)
  while session.running and (session_connection.monotonic() - session.last_activity) < constants.IDLE_GAP_SEC do
    socket.sleep(0.01)
  end
end

function session_connection.send_packet(session, packet)
  session_connection.ensure_idle_gap(session)
  local ok, err = transport.send_all(session.sock, packet)
  if ok == nil then
    session:_disconnect(err or "send_failed")
    return false
  end
  session.last_activity = session_connection.monotonic()
  return true
end

return session_connection

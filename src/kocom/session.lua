local cosock = require "cosock"
local socket = require "cosock.socket"
local log = require "log"

local child_devices = require "child_devices"
local constants = require "constants"
local emitter = require "emitter"
local parser = require "kocom.parser"
local protocol = require "kocom.protocol"
local Registry = require "kocom.registry"
local transport = require "kocom.transport"

local Session = {}
Session.__index = Session

local function monotonic()
  return socket.gettime()
end

function Session.new(driver, parent_device, config)
  local tx, rx = cosock.channel.new()
  return setmetatable({
    driver = driver,
    parent_device = parent_device,
    config = config,
    command_tx = tx,
    command_rx = rx,
    parser = parser.new(),
    registry = Registry.new(),
    running = false,
    sock = nil,
    last_activity = 0,
    backoff = constants.RECONNECT_MIN_SEC,
    connected = false,
    active_matcher = nil,
    active_match_hit = false,
  }, Session)
end

function Session:enqueue_command(command)
  if self.command_tx ~= nil then
    self.command_tx:send({ type = "command", payload = command })
  end
end

function Session:enqueue_control(control)
  if self.command_tx ~= nil then
    self.command_tx:send(control)
  end
end

function Session:mark_parent_online()
  if self.connected then
    return
  end
  self.connected = true
  self.parent_device:online()
  for _, child in ipairs(child_devices.iter_children(self.driver, self.parent_device)) do
    child:online()
  end
end

function Session:mark_parent_offline(reason)
  self.connected = false
  self.parent_device:set_field(constants.FIELDS.last_error, reason, { persist = true })
  self.parent_device:offline()
  for _, child in ipairs(child_devices.iter_children(self.driver, self.parent_device)) do
    child:offline()
  end
end

function Session:_seed_registry_from_children()
  for _, child in ipairs(child_devices.iter_children(self.driver, self.parent_device)) do
    local update = child:get_field(constants.FIELDS.last_update)
    if type(update) == "table" and update.key ~= nil then
      self.registry:set(update)
    end
  end
end

function Session:_log_special_frame(frame)
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
      self.parent_device.id,
      frame.packet_hex,
      frame.packet_type or 0,
      frame.command or 0,
      #extras > 0 and (" " .. table.concat(extras, " ")) or ""
    )
  )
end

function Session:_connect()
  if not self.config.is_configured then
    return false
  end

  local sock, err = transport.connect(self.config.host, self.config.port)
  if sock == nil then
    self:mark_parent_offline(err or "connect_failed")
    log.warn(string.format("[%s] failed to connect %s:%s (%s)", self.parent_device.id, self.config.host, self.config.port, err or "unknown"))
    return false
  end

  self.sock = sock
  self.last_activity = monotonic()
  self.backoff = constants.RECONNECT_MIN_SEC
  self:mark_parent_online()
  log.info_with({ hub_logs = true }, string.format("[%s] connected to %s:%s", self.parent_device.id, self.config.host, self.config.port))
  return true
end

function Session:_disconnect(reason)
  if self.sock ~= nil then
    transport.close(self.sock)
    self.sock = nil
  end
  self:mark_parent_offline(reason or "disconnected")
end

function Session:_sleep_for_backoff()
  local delay = self.backoff
  self.backoff = math.min(self.backoff * 2, constants.RECONNECT_MAX_SEC)
  socket.sleep(delay)
end

function Session:_read_available()
  if self.sock == nil then
    return false
  end

  local data, err, partial = self.sock:receive(constants.READ_SIZE)
  local chunk = data or partial
  if chunk ~= nil and chunk ~= "" then
    self.last_activity = monotonic()
    for _, frame in ipairs(self.parser:feed(chunk)) do
      local ok, reason = parser.validate_frame(frame)
      if ok then
        self:_handle_frame(frame)
      elseif self.config.debug_unknown_frames then
        log.debug(string.format("[%s] invalid frame dropped: %s", self.parent_device.id, reason))
      end
    end
    return true
  end

  if err ~= nil and err ~= "timeout" then
    log.warn(string.format("[%s] receive error: %s", self.parent_device.id, err))
    self:_disconnect(err)
    return false
  end
  return true
end

function Session:_handle_updates(updates)
  for _, update in ipairs(updates) do
    self.registry:set(update)
    child_devices.ensure_child(self.driver, self.parent_device, update)
    if self.active_matcher ~= nil and self.active_matcher(update) then
      self.active_match_hit = true
    end
    emitter.apply_update(self.driver, self.parent_device, update)
  end
end

function Session:_handle_frame(frame)
  local frame_info
  if self.config.capture_special_frames then
    frame_info = protocol.inspect_frame(frame, self.config)
  end

  local updates = protocol.decode_frame(frame, self.config)
  if #updates == 0 then
    if self.config.debug_unknown_frames then
      log.debug(string.format("[%s] no logical update for frame", self.parent_device.id))
    end
    if self.config.capture_special_frames then
      self:_log_special_frame(frame_info)
    end
  end
  self:_handle_updates(updates)
end

function Session:_ensure_idle_gap()
  while self.running and (monotonic() - self.last_activity) < constants.IDLE_GAP_SEC do
    socket.sleep(0.01)
  end
end

function Session:_send_packet(packet)
  self:_ensure_idle_gap()
  local ok, err = transport.send_all(self.sock, packet)
  if ok == nil then
    self:_disconnect(err or "send_failed")
    return false
  end
  self.last_activity = monotonic()
  return true
end

function Session:_wait_for_match(timeout_sec)
  local deadline = monotonic() + timeout_sec
  while self.running and self.sock ~= nil and monotonic() < deadline do
    local recvt, _, err = socket.select({ self.sock }, nil, constants.RECV_TIMEOUT)
    if err ~= nil and err ~= "timeout" then
      self:_disconnect(err)
      return false
    end
    if recvt and (recvt[1] == self.sock or recvt[2] == self.sock) then
      self:_read_available()
      if self.active_match_hit then
        return true
      end
    end
  end
  return self.active_match_hit
end

function Session:_process_command(command)
  if self.sock == nil and not self:_connect() then
    return
  end

  local packet, matcher, timeout_sec, err = protocol.build_command(self.config, self.registry, command.child_key, command.action, command.args or {})
  if packet == nil then
    log.warn(string.format("[%s] unable to build command %s for %s: %s", self.parent_device.id, command.action, tostring(command.child_key), err or "unknown"))
    return
  end

  local effective_timeout = timeout_sec or 0
  for attempt = 1, constants.SEND_RETRY_MAX do
    if self.sock == nil and not self:_connect() then
      return
    end

    if not self:_send_packet(packet) then
      if attempt < constants.SEND_RETRY_MAX then
        self:_sleep_for_backoff()
      end
    else
      if matcher == nil or effective_timeout <= 0 then
        return
      end

      self.active_matcher = matcher
      self.active_match_hit = false
      if self:_wait_for_match(effective_timeout) then
        self.active_matcher = nil
        self.active_match_hit = false
        return
      end
      self.active_matcher = nil
      self.active_match_hit = false
    end

    socket.sleep(constants.SEND_RETRY_GAP_SEC)
  end

  log.warn(string.format("[%s] command %s did not confirm for %s", self.parent_device.id, command.action, command.child_key))
end

function Session:replay_child(child_key)
  local update = self.registry:get(child_key)
  if update ~= nil then
    emitter.apply_update(self.driver, self.parent_device, update)
  end
end

function Session:_handle_control(message)
  if message.type == "stop" then
    self.running = false
    return
  end

  if message.type == "monitor" or message.type == "refresh" then
    if self.sock == nil and self.config.is_configured then
      self:_connect()
    end
  end
end

function Session:_finalize_stop()
  local current_session = self.driver.datastore.sessions and self.driver.datastore.sessions[self.parent_device.id]
  if current_session == self then
    self:_disconnect("stopped")
  else
    self.connected = false
    if self.sock ~= nil then
      transport.close(self.sock)
      self.sock = nil
    end
  end

  if self.command_rx ~= nil then
    pcall(self.command_rx.close, self.command_rx)
  end
end

function Session:start()
  if self.running then
    return
  end

  self.running = true
  self:_seed_registry_from_children()
  cosock.spawn(function()
    while self.running do
      if self.sock == nil and self.config.is_configured then
        if not self:_connect() then
          self:_sleep_for_backoff()
        end
      end

      local read_set = { self.command_rx }
      if self.sock ~= nil then
        table.insert(read_set, self.sock)
      end
      local recvt, _, err = socket.select(read_set, nil, constants.RECV_TIMEOUT)
      if err ~= nil and err ~= "timeout" then
        log.warn(string.format("[%s] session select error: %s", self.parent_device.id, err))
      end

      if recvt ~= nil then
        for _, ready in ipairs(recvt) do
          if ready == self.command_rx then
            local message = self.command_rx:receive()
            if message ~= nil and message.type == "command" then
              self:_process_command(message.payload)
            elseif message ~= nil then
              self:_handle_control(message)
            end
          elseif ready == self.sock then
            self:_read_available()
          end
        end
      end
    end

    self:_finalize_stop()
  end, string.format("kocom-session-%s", self.parent_device.id))
end

function Session:stop()
  if not self.running then
    return
  end
  self.running = false
  if self.command_tx ~= nil then
    self.command_tx:send({ type = "stop" })
  end
end

return Session

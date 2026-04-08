local cosock = require "cosock"
local socket = require "cosock.socket"
local log = require "log"

local constants = require "constants"
local emitter = require "emitter"
local parser = require "kocom.parser"
local Registry = require "kocom.registry"
local session_commands = require "kocom.session_commands"
local session_connection = require "kocom.session_connection"
local session_frames = require "kocom.session_frames"
local session_state = require "kocom.session_state"

local Session = {}
Session.__index = Session

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
  session_state.mark_parent_online(self)
end

function Session:mark_parent_offline(reason)
  session_state.mark_parent_offline(self, reason)
end

function Session:_seed_registry_from_children()
  session_state.seed_registry_from_children(self)
end

function Session:_log_special_frame(frame)
  session_frames.log_special_frame(self, frame)
end

function Session:_connect()
  return session_connection.connect(self)
end

function Session:_disconnect(reason)
  session_connection.disconnect(self, reason)
end

function Session:_sleep_for_backoff()
  session_connection.sleep_for_backoff(self)
end

function Session:_read_available()
  return session_frames.read_available(self)
end

function Session:_handle_updates(updates)
  session_frames.handle_updates(self, updates)
end

function Session:_handle_frame(frame)
  session_frames.handle_frame(self, frame)
end

function Session:_ensure_idle_gap()
  session_connection.ensure_idle_gap(self)
end

function Session:_send_packet(packet)
  return session_connection.send_packet(self, packet)
end

function Session:_wait_for_match(timeout_sec)
  return session_commands.wait_for_match(self, timeout_sec)
end

function Session:_process_command(command)
  session_commands.process_command(self, command)
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
  session_state.finalize_stop(self)
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

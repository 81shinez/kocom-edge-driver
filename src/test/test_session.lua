local test = require "integration_test"

local Registry = require "kocom.registry"

local stub_children = {}
local stub_frame_info = {
  packet_hex = "AA55",
  packet_type = 0x00,
  command = 0x10,
  room_index = 1,
}
local stub_updates = {}
local transport_close_calls = 0

local function load_session_module()
  local module_names = {
    "cosock",
    "cosock.socket",
    "child_devices",
    "emitter",
    "kocom.parser",
    "kocom.protocol",
    "kocom.transport",
    "kocom.session",
  }

  local originals = {}
  for _, name in ipairs(module_names) do
    originals[name] = package.loaded[name]
  end

  package.loaded["cosock"] = {
    channel = {
      new = function()
        return {
          send = function() end,
        }, {
          close = function() end,
          receive = function() return nil end,
        }
      end,
    },
    spawn = function(fn)
      return fn()
    end,
  }

  package.loaded["cosock.socket"] = {
    gettime = function() return 0 end,
    sleep = function() end,
    select = function() return {}, nil, "timeout" end,
  }

  package.loaded["child_devices"] = {
    iter_children = function()
      return stub_children
    end,
    make_child_key = function(device_type, room_index, device_index, sub_type)
      return string.format("%s-%d-%d-%s", device_type, room_index, device_index, sub_type)
    end,
  }

  package.loaded["emitter"] = {}
  package.loaded["kocom.parser"] = {
    new = function()
      return {}
    end,
    validate_frame = function()
      return true
    end,
  }
  package.loaded["kocom.protocol"] = {
    inspect_frame = function()
      return stub_frame_info
    end,
    decode_frame = function()
      return stub_updates
    end,
  }
  package.loaded["kocom.transport"] = {
    close = function()
      transport_close_calls = transport_close_calls + 1
    end,
  }
  package.loaded["kocom.session"] = nil

  local session_module = require "kocom.session"
  return session_module, function()
    for _, name in ipairs(module_names) do
      package.loaded[name] = originals[name]
    end
  end
end

local Session, restore = load_session_module()

test.register_coroutine_test(
  "session should seed registry from persisted child updates",
  function()
    stub_children = {
      {
        get_field = function(_, key)
          if key == "last_update" then
            return {
              key = "light-1-1-none",
              value = true,
            }
          end
        end,
      },
    }

    local session = setmetatable({
      driver = {},
      parent_device = { id = "parent-1" },
      registry = Registry.new(),
    }, Session)

    session:_seed_registry_from_children()

    local update = session.registry:get("light-1-1-none")
    assert(update ~= nil and update.value == true, "persisted child update should restore registry state")
  end
)

test.register_coroutine_test(
  "session should log special frame hints when capture is enabled",
  function()
    stub_updates = {}
    stub_frame_info = {
      packet_hex = "AA5530BC",
      packet_type = 0x00,
      command = 0x11,
      room_index = 2,
      peer_code = 0x77,
    }

    local logged = 0
    local session = setmetatable({
      config = {
        capture_special_frames = true,
        debug_unknown_frames = false,
      },
      parent_device = { id = "parent-1" },
      _handle_updates = function() end,
      _log_special_frame = function(_, frame)
        logged = logged + 1
        assert(frame.room_index == 2, "captured frame details should be passed through")
      end,
    }, Session)

    session:_handle_frame("raw-frame")

    assert(logged == 1, "captureSpecialFrames should trigger special frame logging")
  end
)

test.register_coroutine_test(
  "session should not mark devices offline when a replacement session exists",
  function()
    transport_close_calls = 0

    local disconnected = 0
    local session = setmetatable({
      driver = {
        datastore = {
          sessions = {
            ["parent-1"] = {},
          },
        },
      },
      parent_device = { id = "parent-1" },
      sock = {},
      command_rx = {
        close = function(self)
          self.closed = true
        end,
      },
      _disconnect = function()
        disconnected = disconnected + 1
      end,
    }, Session)

    session:_finalize_stop()

    assert(disconnected == 0, "replacement session should suppress offline transition")
    assert(transport_close_calls == 1, "socket should still be closed")
    assert(session.sock == nil, "socket reference should be cleared")
  end
)

local ok, err = pcall(function()
  if test.run_registered_tests then
    test.run_registered_tests()
  else
    run_registered_tests()
  end
end)

restore()
assert(ok, err)

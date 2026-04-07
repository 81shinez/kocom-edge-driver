local test = require "integration_test"

local constants = require "constants"

local function load_lifecycle_handlers(stubs)
  local module_names = {
    "preferences",
    "child_devices",
    "emitter",
    "kocom.session",
    "lifecycle_handlers",
  }

  local originals = {}
  for _, name in ipairs(module_names) do
    originals[name] = package.loaded[name]
  end

  for name, value in pairs(stubs) do
    package.loaded[name] = value
  end
  package.loaded["lifecycle_handlers"] = nil

  local handlers = require "lifecycle_handlers"
  return handlers, function()
    for _, name in ipairs(module_names) do
      package.loaded[name] = originals[name]
    end
  end
end

test.register_coroutine_test(
  "lifecycle init should restart parent session when persisted guard is stale",
  function()
    local scheduled = 0
    local started = 0
    local restored

    local ok, err = pcall(function()
      local fake_session = {
        start = function()
          started = started + 1
        end,
        stop = function() end,
      }

      local handlers
      handlers, restored = load_lifecycle_handlers({
        preferences = {
          build_parent_config = function()
            return {
              is_configured = true,
              host = "192.168.0.10",
              port = 8899,
              command_overrides = {},
            }
          end,
        },
        child_devices = {
          parse_child_key = function() return nil end,
          ensure_override_children = function() end,
        },
        emitter = {
          replay_cached_state = function() end,
        },
        ["kocom.session"] = {
          new = function()
            return fake_session
          end,
        },
      })

      local device = {
        id = "parent-1",
        parent_device_id = nil,
        preferences = { host = "192.168.0.10" },
        fields = {
          [constants.FIELDS.init_started] = true,
        },
        thread = {
          call_on_schedule = function(_, _, _, _)
            scheduled = scheduled + 1
          end,
        },
        get_field = function(self, key)
          return self.fields[key]
        end,
        set_field = function(self, key, value)
          self.fields[key] = value
        end,
        online = function() end,
        offline = function() end,
      }

      local driver = {
        datastore = {},
        get_devices = function()
          return {}
        end,
      }

      handlers.init(driver, device)

      assert(scheduled == 1, "parent monitor should be scheduled")
      assert(started == 1, "parent session should be started")
      assert(driver.datastore.sessions[device.id] == fake_session, "new session should be registered")
    end)

    if restored ~= nil then
      restored()
    end

    assert(ok, err)
  end
)

if test.run_registered_tests then
  test.run_registered_tests()
else
  run_registered_tests()
end

local test = require "integration_test"

local discovery = require "discovery"

local function fake_parent(device_network_id, host)
  return {
    profile = { id = "gateway" },
    preferences = { host = host },
    device_network_id = device_network_id,
  }
end

test.register_coroutine_test(
  "discovery should create a parent when none exists",
  function()
    local created
    local driver = {
      get_devices = function()
        return {}
      end,
      try_create_device = function(_, metadata)
        created = metadata
        return true
      end,
    }

    discovery.discovery_handler(driver, nil, function() return true end)

    assert(created ~= nil, "expected discovery metadata to be created")
    assert(created.type == "LAN", "expected LAN parent")
    assert(created.profile == "gateway", "expected gateway profile")
  end
)

test.register_coroutine_test(
  "discovery should skip when an unconfigured parent exists",
  function()
    local create_calls = 0
    local driver = {
      get_devices = function()
        return {
          fake_parent("kocom-gateway-1", ""),
        }
      end,
      try_create_device = function()
        create_calls = create_calls + 1
        return true
      end,
    }

    discovery.discovery_handler(driver, nil, function() return true end)
    assert(create_calls == 0, "expected no new device when unconfigured parent exists")
  end
)

if test.run_registered_tests then
  test.run_registered_tests()
else
  run_registered_tests()
end

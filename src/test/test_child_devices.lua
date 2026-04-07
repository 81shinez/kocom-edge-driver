local test = require "integration_test"

local child_devices = require "child_devices"

test.register_coroutine_test(
  "child key should round-trip through make and parse",
  function()
    local key = child_devices.make_child_key("light", 1, 0, "none")
    local parsed = child_devices.parse_child_key(key)

    assert(key == "light-1-0-none", "unexpected child key format")
    assert(parsed ~= nil, "parsed child key should not be nil")
    assert(parsed.device_type == "light", "device_type should match")
    assert(parsed.room_index == 1, "room index should match")
    assert(parsed.device_index == 0, "device index should match")
    assert(parsed.sub_type == "none", "sub type should match")
  end
)

if test.run_registered_tests then
  test.run_registered_tests()
else
  run_registered_tests()
end

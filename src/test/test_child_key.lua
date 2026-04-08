local test = require "integration_test"

local child_key = require "child_key"

test.register_coroutine_test(
  "child_key should round-trip through make and parse",
  function()
    local key = child_key.make("light", 1, 0, "none")
    local parsed = child_key.parse(key)

    assert(key == "light-1-0-none", "unexpected child key format")
    assert(parsed ~= nil, "parsed child key should not be nil")
    assert(parsed.device_type == "light", "device_type should match")
    assert(parsed.room_index == 1, "room index should match")
    assert(parsed.device_index == 0, "device index should match")
    assert(parsed.sub_type == "none", "sub type should match")
  end
)

test.register_coroutine_test(
  "child_key should reject malformed keys",
  function()
    assert(child_key.parse("light-A-0-none") == nil, "non-numeric room index must be rejected")
    assert(child_key.parse("light-1-none") == nil, "missing segments must be rejected")
  end
)

if test.run_registered_tests then
  test.run_registered_tests()
else
  run_registered_tests()
end

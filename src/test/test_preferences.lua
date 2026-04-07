local test = require "integration_test"

local preferences = require "preferences"

test.register_coroutine_test(
  "preferences should normalize defaults and parse json",
  function()
    local device = {
      id = "parent-1",
      preferences = {
        host = " 192.168.0.10 ",
        port = 0,
        protocolPreset = "kocom-default",
        deviceCodeOverrides = "{\"light\":\"0x0E\"}",
        commandOverrides = "{\"door\":{\"push\":{\"packetHex\":\"AA55\"}}}",
        debugUnknownFrames = true,
        captureSpecialFrames = false,
      },
    }

    local config = preferences.build_parent_config(device)
    assert(config.host == "192.168.0.10", "host should be trimmed")
    assert(config.port == 8899, "default port should be applied")
    assert(config.is_configured == true, "host should make device configured")
    assert(config.device_code_overrides.light == "0x0E", "device override should be parsed")
    assert(config.command_overrides.door.push.packetHex == "AA55", "command override should be parsed")
    assert(config.debug_unknown_frames == true, "debug flag should be preserved")
  end
)

if test.run_registered_tests then
  test.run_registered_tests()
else
  run_registered_tests()
end

local test = require "integration_test"

local protocol = require "kocom.protocol"
local Registry = require "kocom.registry"

local function build_frame(body)
  local checksum = 0
  for _, value in ipairs(body) do
    checksum = (checksum + value) % 256
  end

  local chars = { string.char(0xAA), string.char(0x55) }
  for _, value in ipairs(body) do
    table.insert(chars, string.char(value))
  end
  table.insert(chars, string.char(checksum))
  table.insert(chars, string.char(0x0D))
  table.insert(chars, string.char(0x0D))
  return table.concat(chars)
end

test.register_coroutine_test(
  "protocol should decode light status into 8 child updates",
  function()
    local frame = build_frame({
      0x30, 0xBC, 0x00, 0x01, 0x00, 0x0E, 0x01, 0x00,
      0xFF, 0x00, 0xFF, 0x00, 0x00, 0x00, 0x00, 0x00,
    })
    local updates = protocol.decode_frame(frame, {})
    assert(#updates == 8, "light frame should decode into 8 switch states")
    assert(updates[1].key == "light-1-0-none", "first light key should match")
    assert(updates[1].value == true, "first light should be on")
    assert(updates[2].value == false, "second light should be off")
  end
)

test.register_coroutine_test(
  "protocol should build a light on command using cached sibling state",
  function()
    local registry = Registry.new()
    for index = 0, 7 do
      registry:set({ key = string.format("light-1-%d-none", index), value = index == 1 })
    end
    local packet = protocol.build_command({}, registry, "light-1-0-none", "turn_on", {})
    assert(packet ~= nil, "packet should be generated")
  end
)

test.register_coroutine_test(
  "protocol should reject switch packet generation when sibling state is unknown",
  function()
    local registry = Registry.new()
    registry:set({ key = "light-1-0-none", value = false })

    local packet, _, _, err = protocol.build_command({}, registry, "light-1-0-none", "turn_on", {})
    assert(packet == nil, "packet should not be generated without sibling cache")
    assert(err ~= nil and err:match("missing cached sibling state"), "missing sibling cache should be reported")
  end
)

test.register_coroutine_test(
  "protocol should build elevator packet with wallpad as source",
  function()
    local registry = Registry.new()
    local packet = protocol.build_command({}, registry, "elevator-3-0-none", "push", {})

    assert(packet ~= nil, "packet should be generated")
    assert(string.byte(packet, 6) == 0x44, "destination device should be elevator")
    assert(string.byte(packet, 7) == 0x03, "destination room should match child key")
    assert(string.byte(packet, 8) == 0x01, "source device should be wallpad")
    assert(string.byte(packet, 9) == 0x00, "source room should remain 0")
    assert(string.byte(packet, 10) == 0x01, "command should be elevator call")
  end
)

test.register_coroutine_test(
  "protocol should build elevator packet from switch on action",
  function()
    local registry = Registry.new()
    local packet = protocol.build_command({}, registry, "elevator-1-0-none", "turn_on", {})
    assert(packet ~= nil, "packet should be generated for switch on")
    assert(string.byte(packet, 10) == 0x01, "command should remain elevator call")
  end
)

test.register_coroutine_test(
  "protocol should decode elevator idle frame as inactive",
  function()
    local frame = build_frame({
      0x30, 0xBC, 0x00, 0x01, 0x00, 0x44, 0x03, 0x00,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    })

    local updates = protocol.decode_frame(frame, {})
    assert(#updates == 1, "elevator frame should decode into one update")
    assert(type(updates[1].value) == "table", "elevator value should be table")
    assert(updates[1].value.direction == "idle", "direction should be idle")
    assert(updates[1].value.active == false, "idle direction should be inactive for switch mirroring")
  end
)

test.register_coroutine_test(
  "protocol should decode gas command 0x01 as non-closed state",
  function()
    local frame = build_frame({
      0x30, 0xBC, 0x00, 0x01, 0x00, 0x2C, 0x01, 0x01,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    })

    local updates = protocol.decode_frame(frame, {})
    assert(#updates == 1, "gas frame should decode into one update")
    assert(updates[1].device_type == "gas", "device type should be gas")
    assert(updates[1].value.valve == "unknown", "0x01 should be treated as non-closed state")
  end
)

test.register_coroutine_test(
  "protocol should reject unsupported gas open command",
  function()
    local registry = Registry.new()
    local packet, _, _, err = protocol.build_command({}, registry, "gas-1-0-none", "open", {})
    assert(packet == nil, "gas open packet should not be generated")
    assert(err ~= nil and err:match("unsupported gas action"), "gas open should be explicitly rejected")
  end
)

if test.run_registered_tests then
  test.run_registered_tests()
else
  run_registered_tests()
end

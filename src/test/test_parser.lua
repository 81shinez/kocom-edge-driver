local test = require "integration_test"

local parser = require "kocom.parser"

local function build_frame(body)
  local checksum = 0
  for _, value in ipairs(body) do
    checksum = (checksum + value) % 256
  end

  local bytes = { 0xAA, 0x55 }
  for _, value in ipairs(body) do
    table.insert(bytes, value)
  end
  table.insert(bytes, checksum)
  table.insert(bytes, 0x0D)
  table.insert(bytes, 0x0D)
  local chars = {}
  for _, value in ipairs(bytes) do
    table.insert(chars, string.char(value))
  end
  return table.concat(chars)
end

test.register_coroutine_test(
  "parser should split valid frames and ignore leading noise",
  function()
    local frame = build_frame({
      0x30, 0xBC, 0x00, 0x0E, 0x01, 0x01, 0x00, 0x00,
      0xFF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    })

    local instance = parser.new()
    local frames = instance:feed(string.char(0x00, 0x01) .. frame .. frame)
    assert(#frames == 2, "expected two parsed frames")
    assert(parser.validate_frame(frames[1]) == true, "first frame should be valid")
  end
)

if test.run_registered_tests then
  test.run_registered_tests()
else
  run_registered_tests()
end

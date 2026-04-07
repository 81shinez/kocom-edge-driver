local constants = require "constants"

local parser = {}

local Parser = {}
Parser.__index = Parser

local function checksum(raw)
  local sum = 0
  for idx = 3, 18 do
    sum = (sum + string.byte(raw, idx)) % 256
  end
  return sum
end

function parser.checksum(raw)
  return checksum(raw)
end

function parser.validate_frame(raw)
  if type(raw) ~= "string" or #raw ~= constants.PACKET_LEN then
    return false, "invalid_length"
  end
  if raw:sub(1, 2) ~= constants.PACKET_PREFIX then
    return false, "invalid_prefix"
  end
  if raw:sub(-2) ~= constants.PACKET_SUFFIX then
    return false, "invalid_suffix"
  end
  if checksum(raw) ~= string.byte(raw, 19) then
    return false, "invalid_checksum"
  end
  return true
end

function Parser.new()
  return setmetatable({
    buffer = "",
  }, Parser)
end

function Parser:feed(chunk)
  local frames = {}
  if chunk == nil or chunk == "" then
    return frames
  end

  self.buffer = self.buffer .. chunk

  while true do
    local start_pos = string.find(self.buffer, constants.PACKET_PREFIX, 1, true)
    if start_pos == nil then
      self.buffer = ""
      break
    end

    if start_pos > 1 then
      self.buffer = self.buffer:sub(start_pos)
    end

    if #self.buffer < constants.PACKET_LEN then
      break
    end

    local candidate = self.buffer:sub(1, constants.PACKET_LEN)
    if candidate:sub(-2) ~= constants.PACKET_SUFFIX then
      self.buffer = self.buffer:sub(2)
    else
      table.insert(frames, candidate)
      self.buffer = self.buffer:sub(constants.PACKET_LEN + 1)
    end
  end

  return frames
end

parser.new = Parser.new

return parser

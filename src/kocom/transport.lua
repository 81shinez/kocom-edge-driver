local socket = require "cosock.socket"

local constants = require "constants"

local transport = {}

function transport.connect(host, port)
  local sock = socket.tcp()
  sock:settimeout(constants.CONNECT_TIMEOUT)
  local ok, err = sock:connect(host, port)
  if ok == nil then
    return nil, err
  end
  sock:settimeout(0)
  return sock
end

function transport.close(sock)
  if sock ~= nil then
    pcall(sock.close, sock)
  end
end

function transport.send_all(sock, payload)
  local index = 1
  while index <= #payload do
    local sent, err, last = sock:send(payload, index)
    if sent == nil then
      if err ~= "timeout" then
        return nil, err
      end
      index = (last or index - 1) + 1
    else
      index = sent + 1
    end
  end

  return true
end

return transport

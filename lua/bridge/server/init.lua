--- MCP JSON-RPC message handler and WebSocket server management
local tcp = require("bridge.server.tcp")
local frame = require("bridge.server.frame")

local M = {}

M.state = {
  server = nil,
  timer = nil,
  handlers = {},
}

---Register the MCP protocol handlers
local function register_handlers()
  M.state.handlers = {
    ["initialize"] = function()
      return {
        protocolVersion = "2024-11-05",
        capabilities = {
          tools = { listChanged = false },
        },
        serverInfo = {
          name = "agent-bridge-nvim",
          version = "0.1.0",
        },
      }
    end,

    ["notifications/initialized"] = function() end,

    ["prompts/list"] = function()
      return { prompts = {} }
    end,

    ["resources/list"] = function()
      return { resources = {} }
    end,

    ["tools/list"] = function()
      return { tools = {} }
    end,

    ["tools/call"] = function()
      return nil, { code = -32601, message = "No tools implemented" }
    end,
  }
end

---Handle a JSON-RPC request
---@param client WebSocketClient The client that sent the request
---@param request table The parsed JSON-RPC request
local function handle_request(client, request)
  local method = request.method
  local handler = M.state.handlers[method]

  if not handler then
    M.send_response(client, request.id, nil, {
      code = -32601,
      message = "Method not found: " .. method,
    })
    return
  end

  local result, err = handler(client, request.params)

  if request.id then
    M.send_response(client, request.id, result, err)
  end
end

---Handle an incoming WebSocket message (JSON-RPC 2.0)
---@param client WebSocketClient The client that sent the message
---@param message string The raw message text
local function handle_message(client, message)
  local ok, request = pcall(vim.json.decode, message)
  if not ok or type(request) ~= "table" then
    return
  end

  handle_request(client, request)
end

---Send a JSON-RPC response to a client
---@param client WebSocketClient The client to respond to
---@param id any The request ID
---@param result any The result (if success)
---@param error_data table|nil The error (if failure)
function M.send_response(client, id, result, error_data)
  local response = {
    jsonrpc = "2.0",
    id = id,
  }

  if error_data then
    response.error = error_data
  else
    response.result = result or {}
  end

  local json = vim.json.encode(response)
  local text_frame = frame.create_text_frame(json)
  client.tcp_handle:write(text_frame)
end

---Broadcast a JSON-RPC notification to all connected clients
---@param method string The notification method name
---@param params table The notification parameters
function M.broadcast(method, params)
  if not M.state.server then
    return
  end

  local notification = vim.json.encode({
    jsonrpc = "2.0",
    method = method,
    params = params,
  })

  tcp.broadcast(M.state.server, notification)
end

---Start the MCP server
---@param config table Server configuration
---@param auth_token string Authentication token
---@param on_connect function|nil Optional callback when a client connects
---@param on_disconnect function|nil Optional callback when a client disconnects
---@return number|nil port The port the server is listening on, or nil on error
---@return string|nil error Error message if failed
function M.start(config, auth_token, on_connect, on_disconnect)
  register_handlers()

  local server, err = tcp.create_server(config, {
    on_message = function(client, message)
      handle_message(client, message)
    end,
    on_connect = function(client)
      if on_connect then
        vim.schedule(function()
          on_connect(client)
        end)
      end
    end,
    on_disconnect = function(client, code, reason)
      if on_disconnect then
        vim.schedule(function()
          on_disconnect(client, code, reason)
        end)
      end
    end,
    on_error = function(err_msg)
      vim.schedule(function()
        vim.notify("[bridge] " .. err_msg, vim.log.levels.ERROR)
      end)
    end,
  }, auth_token)

  if not server then
    return nil, err
  end

  M.state.server = server
  M.state.timer = tcp.start_ping_timer(server, 30000)

  return server.port, nil
end

---Stop the MCP server
function M.stop()
  if M.state.timer then
    M.state.timer:stop()
    M.state.timer:close()
    M.state.timer = nil
  end

  if M.state.server then
    tcp.stop_server(M.state.server)
    M.state.server = nil
  end

  M.state.handlers = {}
end

---Get the number of connected clients
---@return number count
function M.get_client_count()
  if not M.state.server then
    return 0
  end
  return tcp.get_client_count(M.state.server)
end

return M

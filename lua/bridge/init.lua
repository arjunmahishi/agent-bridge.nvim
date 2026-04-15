--- agent-bridge.nvim: Minimal bridge from Neovim to external AI coding agents
local server = require("bridge.server")
local lockfile = require("bridge.lockfile")

local M = {}

local defaults = {
  auto_start = true,
  port_range = { min = 10000, max = 65535 },
  agents = {
    claude = { lock_dir = "~/.claude/ide" },
  },
}

M.state = {
  config = nil,
  port = nil,
  auth_token = nil,
  running = false,
}

---Merge user config with defaults (one level deep)
---@param user_opts table|nil
---@return table
local function merge_config(user_opts)
  if not user_opts then
    return vim.deepcopy(defaults)
  end

  local config = vim.deepcopy(defaults)
  for k, v in pairs(user_opts) do
    if type(v) == "table" and type(config[k]) == "table" then
      for kk, vv in pairs(v) do
        config[k][kk] = vv
      end
    else
      config[k] = v
    end
  end
  return config
end

---Start the WebSocket MCP server and write lockfiles
---@return number|nil port The port, or nil on error
function M.start()
  if M.state.running then
    vim.notify("[bridge] Already running on port " .. M.state.port, vim.log.levels.WARN)
    return M.state.port
  end

  M.state.auth_token = lockfile.generate_auth_token()

  local port, err = server.start(
    M.state.config,
    M.state.auth_token,
    function() -- on_connect
      vim.notify("[bridge] Agent connected", vim.log.levels.INFO)
    end,
    function() -- on_disconnect
      vim.notify("[bridge] Agent disconnected", vim.log.levels.INFO)
    end
  )

  if not port then
    vim.notify("[bridge] Failed to start: " .. (err or "unknown error"), vim.log.levels.ERROR)
    return nil
  end

  lockfile.create_all(port, M.state.auth_token, M.state.config.agents)

  M.state.port = port
  M.state.running = true
  vim.notify("[bridge] Listening on port " .. port, vim.log.levels.INFO)
  return port
end

---Stop the server and remove lockfiles
function M.stop()
  if not M.state.running then
    return
  end

  server.stop()

  if M.state.port then
    lockfile.remove_all(M.state.port, M.state.config.agents)
  end

  M.state.port = nil
  M.state.auth_token = nil
  M.state.running = false
  vim.notify("[bridge] Stopped", vim.log.levels.INFO)
end

---Get the current status
---@return table status { running, port, clients }
function M.status()
  return {
    running = M.state.running,
    port = M.state.port,
    clients = server.get_client_count(),
  }
end

---Check if any agent is connected
---@return boolean
function M.is_connected()
  return server.get_client_count() > 0
end

---Send an at_mentioned notification to all connected agents
---@param file_path string Absolute path to the file
---@param start_line number|nil 0-indexed start line (nil for whole file)
---@param end_line number|nil 0-indexed end line (nil for whole file)
---@param comment string|nil Optional comment text
function M.send(file_path, start_line, end_line, comment)
  if not M.state.running then
    vim.notify("[bridge] Not running. Call :BridgeStart first", vim.log.levels.WARN)
    return
  end

  if not M.is_connected() then
    vim.notify("[bridge] No agent connected", vim.log.levels.WARN)
    return
  end

  local params = {
    filePath = file_path,
    lineStart = start_line,
    lineEnd = end_line,
  }
  if comment and comment ~= "" then
    params.comment = comment
  end

  server.broadcast("at_mentioned", params)
end

---Initialize the plugin
---@param opts table|nil User configuration
function M.setup(opts)
  M.state.config = merge_config(opts)

  -- User commands
  vim.api.nvim_create_user_command("BridgeStart", function()
    M.start()
  end, { desc = "Start agent bridge server" })

  vim.api.nvim_create_user_command("BridgeStop", function()
    M.stop()
  end, { desc = "Stop agent bridge server" })

  vim.api.nvim_create_user_command("BridgeStatus", function()
    local s = M.status()
    if s.running then
      vim.notify(
        string.format("[bridge] Running on port %d, %d client(s) connected", s.port, s.clients),
        vim.log.levels.INFO
      )
    else
      vim.notify("[bridge] Not running", vim.log.levels.INFO)
    end
  end, { desc = "Show agent bridge status" })

  vim.api.nvim_create_user_command("BridgeSend", function(cmd_opts)
    local file_path = vim.api.nvim_buf_get_name(0)
    if file_path == "" then
      vim.notify("[bridge] No file in current buffer", vim.log.levels.WARN)
      return
    end

    local start_line, end_line
    if cmd_opts.range > 0 then
      start_line = cmd_opts.line1 - 1
      end_line = cmd_opts.line2 - 1
    else
      local cursor_line = vim.api.nvim_win_get_cursor(0)[1] - 1
      start_line = cursor_line
      end_line = cursor_line
    end

    vim.ui.input({ prompt = "Comment: " }, function(comment)
      if comment == nil then return end
      M.send(file_path, start_line, end_line, comment)
    end)
  end, { range = true, desc = "Send file/selection to connected agent" })

  -- Cleanup on exit
  vim.api.nvim_create_autocmd("VimLeavePre", {
    callback = function()
      M.stop()
    end,
  })

  -- Auto-start if configured
  if M.state.config.auto_start then
    M.start()
  end
end

return M

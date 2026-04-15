--- Multi-agent lockfile management for IDE discovery
local M = {}

---Generate a UUID v4 authentication token
---@return string token A UUID v4 string
function M.generate_auth_token()
  math.randomseed(os.time() + vim.fn.getpid() + vim.loop.hrtime())

  local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
  return template:gsub("[xy]", function(c)
    local v = (c == "x") and math.random(0, 15) or math.random(8, 11)
    return string.format("%x", v)
  end)
end

---Create lockfiles for all configured agents
---@param port number The WebSocket server port
---@param auth_token string The authentication token
---@param agents table Agent configuration table (name -> { lock_dir = "..." })
function M.create_all(port, auth_token, agents)
  local content = vim.json.encode({
    pid = vim.fn.getpid(),
    workspaceFolders = { vim.fn.getcwd() },
    ideName = "Neovim",
    transport = "ws",
    authToken = auth_token,
  })

  for _, agent in pairs(agents) do
    local lock_dir = vim.fn.expand(agent.lock_dir)
    vim.fn.mkdir(lock_dir, "p")

    local lock_path = lock_dir .. "/" .. port .. ".lock"
    -- Atomic write: write to tmp then rename
    local tmp_path = lock_path .. ".tmp"
    local file = io.open(tmp_path, "w")
    if file then
      file:write(content)
      file:close()
      vim.loop.fs_rename(tmp_path, lock_path)
    end
  end
end

---Remove lockfiles for all configured agents
---@param port number The WebSocket server port
---@param agents table Agent configuration table
function M.remove_all(port, agents)
  for _, agent in pairs(agents) do
    local lock_path = vim.fn.expand(agent.lock_dir) .. "/" .. port .. ".lock"
    pcall(os.remove, lock_path)
  end
end

return M

--- tmux adapter: list panes, send text
local M = {}

---Check if we're running inside tmux
---@return boolean
function M.is_available()
  return vim.env.TMUX ~= nil and vim.env.TMUX ~= ""
end

---List all tmux panes across all sessions
---@return table[] panes Array of { target, command, path }
function M.list_panes()
  local output = vim.fn.system(
    'tmux list-panes -a -F "#{session_name}:#{window_index}.#{pane_index} #{pane_current_command} #{pane_current_path}"'
  )

  if vim.v.shell_error ~= 0 then
    return {}
  end

  local panes = {}
  for line in output:gmatch("[^\n]+") do
    local target, command, path = line:match("^(%S+)%s+(%S+)%s+(.+)$")
    if target then
      table.insert(panes, { target = target, command = command, path = path })
    end
  end

  return panes
end

---Capture the visible content of a tmux pane
---@param target string The tmux pane target (e.g. "session:0.1")
---@return string content The pane content (empty string on error)
function M.capture_pane(target)
  local output = vim.fn.system(string.format("tmux capture-pane -t '%s' -p", target))
  if vim.v.shell_error ~= 0 then return "" end
  return output
end

---Filter panes to those running any of the given processes
---@param panes table[] Array from list_panes()
---@param processes string[] Process names to match (case-insensitive substring)
---@return table[] filtered
function M.filter_panes(panes, processes)
  return vim.tbl_filter(function(pane)
    local cmd = pane.command:lower()
    for _, proc in ipairs(processes) do
      if cmd:find(proc:lower(), 1, true) then return true end
    end
    return false
  end, panes)
end

---Send text to a tmux pane
---@param target string The tmux pane target (e.g. "session:0.1")
---@param text string The text to send
---@return boolean success
function M.send_text(target, text)
  -- Escape single quotes for shell
  local escaped = text:gsub("'", "'\\''")
  local cmd = string.format("tmux send-keys -t '%s' '%s' Enter", target, escaped)
  vim.fn.system(cmd)
  return vim.v.shell_error == 0
end

return M

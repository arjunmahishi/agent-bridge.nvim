--- agent-bridge.nvim: Send contextual messages from Neovim to external AI agents via tmux
local tmux = require("bridge.tmux")

local M = {}

M.config = {
  processes = { "claude", "opencode" },
}

M.state = {
  target = nil, -- tmux pane target e.g. "mysession:0.1"
}

---Pick a tmux pane to connect to via Telescope with terminal preview
---@param callback function|nil Called after selection with the target string
function M.connect(callback)
  if not tmux.is_available() then
    vim.notify("[bridge] Not inside tmux", vim.log.levels.ERROR)
    return
  end

  local panes = tmux.filter_panes(tmux.list_panes(), M.config.processes)
  if #panes == 0 then
    vim.notify("[bridge] No matching tmux panes found", vim.log.levels.ERROR)
    return
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local previewers = require("telescope.previewers")
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local conf = require("telescope.config").values

  pickers.new({}, {
    prompt_title = "Select target pane",
    finder = finders.new_table({
      results = panes,
      entry_maker = function(pane)
        local display = pane.target .. "  (" .. pane.command .. "  " .. pane.path .. ")"
        return {
          value = pane.target,
          display = display,
          ordinal = display,
        }
      end,
    }),
    sorter = conf.generic_sorter({}),
    previewer = previewers.new_termopen_previewer({
      get_command = function(entry)
        return { "sh", "-c", "tmux capture-pane -t '" .. entry.value .. "' -e -p | less -RSX +G" }
      end,
    }),
    attach_mappings = function(prompt_bufnr)
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        actions.close(prompt_bufnr)
        if not entry then return end
        M.state.target = entry.value
        vim.notify("[bridge] Connected to " .. entry.value, vim.log.levels.INFO)
        if callback then callback(entry.value) end
      end)
      return true
    end,
  }):find()
end

---Send raw text to the connected tmux pane
---@param text string The text to send
function M.send(text)
  if not M.state.target then
    vim.notify("[bridge] Not connected. Run :BridgeConnect first", vim.log.levels.WARN)
    return
  end

  local ok = tmux.send_text(M.state.target, text)
  if not ok then
    vim.notify("[bridge] Failed to send to " .. M.state.target, vim.log.levels.ERROR)
  end
end

---Get the current connection status
---@return table status { connected, target }
function M.status()
  return {
    connected = M.state.target ~= nil,
    target = M.state.target,
  }
end

---Format file context + comment into a sendable string
---@param file_path string
---@param start_line number 1-indexed
---@param end_line number 1-indexed
---@param comment string|nil
---@return string
local function format_message(file_path, start_line, end_line, comment)
  -- Use path relative to cwd when possible
  local cwd = vim.fn.getcwd() .. "/"
  local rel_path = file_path
  if file_path:sub(1, #cwd) == cwd then
    rel_path = file_path:sub(#cwd + 1)
  end

  local line_part
  if start_line == end_line then
    line_part = tostring(start_line)
  else
    line_part = start_line .. "-" .. end_line
  end

  local msg = "@" .. rel_path .. ":" .. line_part
  if comment and comment ~= "" then
    msg = msg .. " " .. comment
  end

  return msg
end

---Initialize the plugin
---@param opts table|nil User configuration (reserved for future use)
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  vim.api.nvim_create_user_command("BridgeConnect", function()
    M.connect()
  end, { desc = "Connect to a tmux pane" })

  vim.api.nvim_create_user_command("BridgeStatus", function()
    local s = M.status()
    if s.connected then
      vim.notify("[bridge] Connected to " .. s.target, vim.log.levels.INFO)
    else
      vim.notify("[bridge] Not connected", vim.log.levels.INFO)
    end
  end, { desc = "Show bridge connection status" })

  vim.api.nvim_create_user_command("BridgeSend", function(cmd_opts)
    local file_path = vim.api.nvim_buf_get_name(0)
    if file_path == "" then
      vim.notify("[bridge] No file in current buffer", vim.log.levels.WARN)
      return
    end

    local start_line, end_line
    if cmd_opts.range > 0 then
      start_line = cmd_opts.line1
      end_line = cmd_opts.line2
    else
      start_line = vim.api.nvim_win_get_cursor(0)[1]
      end_line = start_line
    end

    local do_send = function()
      vim.ui.input({ prompt = "Comment: " }, function(comment)
        if comment == nil then return end
        local msg = format_message(file_path, start_line, end_line, comment)
        M.send(msg)
      end)
    end

    if not M.state.target then
      M.connect(function()
        do_send()
      end)
    else
      do_send()
    end
  end, { range = true, desc = "Send file context + comment to connected agent" })
end

return M

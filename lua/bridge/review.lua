--- review comments: accumulate, review, and batch-send comments
local M = {}

M.state = {
  comments = {},
  ns = vim.api.nvim_create_namespace("bridge_review"),
}
M._next_id = 1
M._review_bufnr = nil

-- ── State management ──────────────────────────────────────

---Add or replace a review comment at a file+range location
---@param file_path string Absolute path
---@param start_line number 1-indexed
---@param end_line number 1-indexed
---@param comment string
---@return table entry The comment entry
function M.add(file_path, start_line, end_line, comment)
  local existing = M.find_by_location(file_path, start_line, end_line)
  if existing then
    existing.comment = comment
    M.refresh_all_extmarks()
    return existing
  end

  local entry = {
    id = M._next_id,
    file_path = file_path,
    start_line = start_line,
    end_line = end_line,
    comment = comment,
  }
  M._next_id = M._next_id + 1
  table.insert(M.state.comments, entry)
  M.refresh_all_extmarks()
  return entry
end

---Remove a comment by id
---@param id number
function M.remove(id)
  for i, c in ipairs(M.state.comments) do
    if c.id == id then
      table.remove(M.state.comments, i)
      M.refresh_all_extmarks()
      return
    end
  end
end

---Edit a comment's text by id
---@param id number
---@param new_comment string
function M.edit(id, new_comment)
  for _, c in ipairs(M.state.comments) do
    if c.id == id then
      c.comment = new_comment
      M.refresh_all_extmarks()
      return
    end
  end
end

---Find an existing comment at exact location
---@param file_path string
---@param start_line number
---@param end_line number
---@return table|nil
function M.find_by_location(file_path, start_line, end_line)
  for _, c in ipairs(M.state.comments) do
    if c.file_path == file_path and c.start_line == start_line and c.end_line == end_line then
      return c
    end
  end
  return nil
end

---@return table[] All pending comments
function M.get_all()
  return M.state.comments
end

---@return number
function M.count()
  return #M.state.comments
end

---Check if any comments exist for a file
---@param file_path string
---@return boolean
function M.has_comments_for_file(file_path)
  for _, c in ipairs(M.state.comments) do
    if c.file_path == file_path then return true end
  end
  return false
end

---Clear all comments
function M.clear()
  M.state.comments = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      vim.api.nvim_buf_clear_namespace(buf, M.state.ns, 0, -1)
    end
  end
end

-- ── Extmarks ──────────────────────────────────────────────

---Place extmarks for comments matching this buffer's file
---@param bufnr number
function M.apply_extmarks(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, M.state.ns, 0, -1)
  local file_path = vim.api.nvim_buf_get_name(bufnr)
  if file_path == "" then return end

  for _, c in ipairs(M.state.comments) do
    if c.file_path == file_path then
      local line = c.start_line - 1 -- 0-indexed
      local line_count = vim.api.nvim_buf_line_count(bufnr)
      if line < line_count then
        local truncated = c.comment
        if #truncated > 50 then
          truncated = truncated:sub(1, 47) .. "..."
        end
        vim.api.nvim_buf_set_extmark(bufnr, M.state.ns, line, 0, {
          sign_text = "☰",
          sign_hl_group = "BridgeReviewSign",
          virt_text = { { "-- [review] " .. truncated, "BridgeReviewVirtText" } },
          virt_text_pos = "eol",
        })
      end
    end
  end
end

---Reapply extmarks across all loaded buffers that have comments
function M.refresh_all_extmarks()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" then
        if M.has_comments_for_file(name) then
          M.apply_extmarks(buf)
        else
          vim.api.nvim_buf_clear_namespace(buf, M.state.ns, 0, -1)
        end
      end
    end
  end
end

-- ── Review buffer ─────────────────────────────────────────

---Get comment index from cursor line in review buffer
---@param cursor_line number 1-indexed cursor line
---@return number|nil index 1-indexed comment index
local function comment_index_from_cursor(cursor_line)
  -- Header is 2 lines, then each comment block is 3 lines
  if cursor_line <= 2 then return nil end
  local idx = math.floor((cursor_line - 3) / 3) + 1
  if idx < 1 or idx > #M.state.comments then return nil end
  return idx
end

---Render the review buffer contents
---@param bufnr number
local function render_review(bufnr)
  local lines = {}
  local count = M.count()
  table.insert(lines, "Bridge Review: " .. count .. " comment" .. (count == 1 and "" or "s") .. " pending")
  table.insert(lines, string.rep("─", 50))

  for i, c in ipairs(M.state.comments) do
    -- Use relative path for display
    local cwd = vim.fn.getcwd() .. "/"
    local display_path = c.file_path
    if c.file_path:sub(1, #cwd) == cwd then
      display_path = c.file_path:sub(#cwd + 1)
    end

    local line_part
    if c.start_line == c.end_line then
      line_part = tostring(c.start_line)
    else
      line_part = c.start_line .. "-" .. c.end_line
    end

    table.insert(lines, i .. ". " .. display_path .. ":" .. line_part)
    table.insert(lines, "   " .. c.comment)
    table.insert(lines, "")
  end

  table.insert(lines, string.rep("─", 50))
  table.insert(lines, "[e]dit  [dd]elete  [Enter]jump  [s]ubmit  [D]iscard  [q]uit")

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
end

---Edit a comment in a floating scratch buffer
---@param entry table The comment entry
---@param on_save function Called with new text when saved
local function edit_in_float(entry, on_save)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(entry.comment, "\n"))
  vim.bo[buf].bufhidden = "wipe"

  local width = math.min(60, vim.o.columns - 4)
  local height = math.min(10, vim.o.lines - 4)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    width = width,
    height = height,
    border = "rounded",
    title = " Edit comment ",
    title_pos = "center",
  })

  vim.bo[buf].modifiable = true

  -- Save on :w
  vim.api.nvim_buf_set_keymap(buf, "n", "<CR>", "", {
    callback = function()
      local new_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local new_text = table.concat(new_lines, "\n")
      vim.api.nvim_win_close(win, true)
      on_save(new_text)
    end,
  })

  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = buf,
    callback = function()
      local new_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
      local new_text = table.concat(new_lines, "\n")
      vim.api.nvim_win_close(win, true)
      on_save(new_text)
    end,
  })

  -- Cancel on q
  vim.api.nvim_buf_set_keymap(buf, "n", "q", "", {
    callback = function()
      vim.api.nvim_win_close(win, true)
    end,
  })
end

---Open the review scratch buffer
function M.open_review()
  if M.count() == 0 then
    vim.notify("[bridge] No pending review comments", vim.log.levels.INFO)
    return
  end

  -- Reuse existing review buffer if still visible
  if M._review_bufnr and vim.api.nvim_buf_is_valid(M._review_bufnr) then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == M._review_bufnr then
        vim.api.nvim_set_current_win(win)
        render_review(M._review_bufnr)
        return
      end
    end
  end

  local buf = vim.api.nvim_create_buf(false, true)
  M._review_bufnr = buf
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "bridge_review"

  vim.cmd("botright split")
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_height(win, math.min(20, M.count() * 3 + 4))

  render_review(buf)

  local opts = { buffer = buf }

  -- Jump to comment location
  vim.keymap.set("n", "<CR>", function()
    local idx = comment_index_from_cursor(vim.api.nvim_win_get_cursor(0)[1])
    if not idx then return end
    local c = M.state.comments[idx]
    vim.api.nvim_win_close(0, true)
    vim.cmd("edit " .. vim.fn.fnameescape(c.file_path))
    vim.api.nvim_win_set_cursor(0, { c.start_line, 0 })
  end, opts)

  -- Edit comment
  vim.keymap.set("n", "e", function()
    local idx = comment_index_from_cursor(vim.api.nvim_win_get_cursor(0)[1])
    if not idx then return end
    local c = M.state.comments[idx]
    edit_in_float(c, function(new_text)
      M.edit(c.id, new_text)
      if vim.api.nvim_buf_is_valid(buf) then
        render_review(buf)
      end
    end)
  end, opts)

  -- Delete comment
  vim.keymap.set("n", "dd", function()
    local idx = comment_index_from_cursor(vim.api.nvim_win_get_cursor(0)[1])
    if not idx then return end
    M.remove(M.state.comments[idx].id)
    if M.count() == 0 then
      vim.api.nvim_win_close(0, true)
      vim.notify("[bridge] All comments removed", vim.log.levels.INFO)
    else
      render_review(buf)
    end
  end, opts)

  -- Submit
  vim.keymap.set("n", "s", function()
    vim.api.nvim_win_close(0, true)
    vim.cmd("BridgeSubmit")
  end, opts)

  -- Discard
  vim.keymap.set("n", "D", function()
    vim.api.nvim_win_close(0, true)
    M.discard()
  end, opts)

  -- Quit
  vim.keymap.set("n", "q", function()
    vim.api.nvim_win_close(0, true)
  end, opts)
end

-- ── Batch operations ──────────────────────────────────────

---Format and send all comments, then clear
---@param send_fn function Receives the full batch text
---@param format_fn function(file_path, start_line, end_line, comment) → string
function M.submit(send_fn, format_fn)
  if M.count() == 0 then
    vim.notify("[bridge] No pending review comments", vim.log.levels.INFO)
    return
  end

  local parts = {}
  for _, c in ipairs(M.state.comments) do
    table.insert(parts, format_fn(c.file_path, c.start_line, c.end_line, c.comment))
  end

  local count = M.count()
  send_fn(table.concat(parts, "\n"))
  M.clear()
  vim.notify("[bridge] Submitted " .. count .. " review comment" .. (count == 1 and "" or "s"), vim.log.levels.INFO)
end

---Discard all comments without sending
function M.discard()
  local count = M.count()
  M.clear()
  if count > 0 then
    vim.notify("[bridge] Discarded " .. count .. " review comment" .. (count == 1 and "" or "s"), vim.log.levels.INFO)
  end
end

-- ── Setup ─────────────────────────────────────────────────

---Register autocmds and highlight groups
---@param augroup number
function M.setup(augroup)
  vim.api.nvim_set_hl(0, "BridgeReviewSign", { default = true, link = "DiagnosticSignInfo" })
  vim.api.nvim_set_hl(0, "BridgeReviewVirtText", { default = true, link = "DiagnosticVirtualTextInfo" })

  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function(args)
      local file_path = vim.api.nvim_buf_get_name(args.buf)
      if file_path ~= "" and M.has_comments_for_file(file_path) then
        M.apply_extmarks(args.buf)
      end
    end,
  })
end

return M

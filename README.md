# agent-bridge.nvim

Send contextual messages from Neovim to AI coding agents running in tmux panes.

Point at code, type a comment, and it lands in your agent's input — no copy-paste, no context switching.

## Features

- **Telescope pane picker** with live colored terminal preview to connect to agent panes
- **Instant send** — select lines, add a comment, send immediately (`@file:line comment`)
- **Review comments** — GitHub-style workflow: accumulate comments across files, review in a buffer, edit/delete, then batch-submit all at once
- **Smart filtering** — only shows panes running AI agents (configurable process list)
- **Visual markers** — sign column icons and virtual text on lines with pending review comments

## Requirements

- Neovim >= 0.9
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- tmux

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "arjunmahishi/agent-bridge.nvim",
  dependencies = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("bridge").setup({
      -- processes to show in the pane picker (default: { "claude", "opencode" })
      processes = { "claude", "opencode" },
    })
  end,
  keys = {
    { "<leader>bs", "<cmd>BridgeSend<cr>", mode = "n", desc = "Send to agent" },
    { "<leader>bs", ":'<,'>BridgeSend<cr>", mode = "v", desc = "Send to agent" },
    { "<leader>bc", "<cmd>BridgeConnect<cr>", desc = "Connect to tmux pane" },
    { "<leader>bt", "<cmd>BridgeStatus<cr>", desc = "Bridge status" },
    { "<leader>ba", "<cmd>BridgeComment<cr>", mode = "n", desc = "Add review comment" },
    { "<leader>ba", ":'<,'>BridgeComment<cr>", mode = "v", desc = "Add review comment" },
    { "<leader>br", "<cmd>BridgeReview<cr>", desc = "Review pending comments" },
    { "<leader>bx", "<cmd>BridgeSubmit<cr>", desc = "Submit review comments" },
    { "<leader>bd", "<cmd>BridgeDiscard<cr>", desc = "Discard review comments" },
  },
}
```

## Usage

### Quick send

1. `:BridgeConnect` — Telescope picker shows agent panes with terminal preview
2. Place cursor on a line (or visual-select a range)
3. `:BridgeSend` — type a comment, it's sent immediately as `@file:line comment`

If you're not connected yet, `:BridgeSend` will prompt you to connect first.

### Review comments

A GitHub PR review-style workflow for batching multiple comments:

1. Navigate to code, run `:BridgeComment` — adds a pending comment with a gutter marker
2. Repeat across multiple files
3. `:BridgeReview` — opens a review buffer listing all pending comments
4. From the review buffer:
   - `Enter` — jump to the comment's location
   - `e` — edit in a floating buffer (`:w` to save, `q` to cancel)
   - `dd` — delete the comment
   - `s` — submit all comments
   - `D` — discard all comments
   - `q` — close without action
5. `:BridgeSubmit` — sends all comments as a single batch message

### Commands

| Command | Description |
|---------|-------------|
| `:BridgeConnect` | Pick a tmux pane to connect to |
| `:BridgeStatus` | Show connection status and pending comment count |
| `:BridgeSend` | Send file context + comment immediately |
| `:BridgeComment` | Add/edit a review comment at current line |
| `:BridgeReview` | Open the review buffer |
| `:BridgeSubmit` | Batch-send all review comments |
| `:BridgeDiscard` | Clear all review comments |

## Configuration

```lua
require("bridge").setup({
  -- List of process names to filter tmux panes by.
  -- Only panes running these processes will appear in the picker.
  -- Uses case-insensitive substring matching.
  processes = { "claude", "opencode" },
})
```

## Message format

Messages are sent as `@<relative-path>:<line-range> <comment>`. For example:

```
@src/server.go:42 fix this off-by-one error
@pkg/util/retry.go:15-20 refactor this into a helper
```

When batch-submitting review comments, all messages are joined with newlines and sent as a single input.

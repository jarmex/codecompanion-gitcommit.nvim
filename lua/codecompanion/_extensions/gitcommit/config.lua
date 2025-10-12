local M = {}

---@class CodeCompanion.GitCommit.ExtensionOpts
M.default_opts = {
  adapter = nil, -- Inherit from global config
  model = nil, -- Inherit from global config
  languages = { "English", "Chinese", "Japanese", "French" },
  exclude_files = {
    "*.pb.go",
    "*.min.js",
    "*.min.css",
    "package-lock.json",
    "yarn.lock",
    "*.log",
    "dist/*",
    "build/*",
    ".next/*",
    "node_modules/*",
    "vendor/*",
  },
  buffer = {
    enabled = true,
    keymap = "<leader>gc",
    auto_generate = true,
    auto_generate_delay = 200,
    skip_auto_generate_on_amend = true, -- Skip auto-generation during git commit --amend
  },
  add_slash_command = true,
  add_git_tool = true,
  enable_git_read = true,
  enable_git_edit = true,
  enable_git_bot = true, -- Only enabled if both enable_git_read and enable_git_edit are true
  add_git_commands = true,
  git_tool_auto_submit_errors = false,
  git_tool_auto_submit_success = true,
  gitcommit_select_count = 100,
  -- History commit context configuration
  use_commit_history = true, -- Enable using commit history as context
  commit_history_count = 10, -- Number of recent commits to include as context
  -- Issue ID extraction from branch name
  include_issue_id_from_branch = false, -- Enable automatic issue ID extraction from branch name
  issue_id_patterns = { -- Patterns for extracting issue IDs from branch names
    { pattern = "^bcd%-(%d%d%d%d)", prefix = "BCD", format = "BCD-%s" },
    { pattern = "MOB%-(%d+)", prefix = "MOB", format = "MOB-%s" },
    { pattern = "TEC%-(%d+)", prefix = "TEC", format = "TEC-%s" },
    { pattern = "ENG%-(%d+)", prefix = "ENG", format = "ENG-%s" },
  },
}

return M

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Neovim plugin extension for CodeCompanion that generates AI-powered Git commit messages following the Conventional Commits specification. It provides comprehensive Git workflow integration through chat tools, slash commands, and buffer integration.

## Development Commands

### Linting and Formatting
- **Format code**: `stylua .` (uses stylua.toml configuration)
- **Documentation**: `make doc` (downloads CodeCompanion documentation for reference)

### Formatting Rules (stylua.toml)
- 2 spaces indentation
- 120 character column width
- Unix line endings
- Auto-prefer double quotes
- No single-statement collapse
- Always use call parentheses

### Testing
No automated test suite exists in this repository. Manual testing is required.

## Architecture Overview

### Core Module Structure

The extension is organized under `lua/codecompanion/_extensions/gitcommit/`:

**Main Modules:**
- **init.lua** - Extension entry point that registers:
  - Slash commands (`/gitcommit`)
  - Chat tools (`@git_read`, `@git_edit`, `@git_bot`, `@ai_release_notes`)
  - User commands (`:CodeCompanionGitCommit`, `:CCGitCommit`)
  - Exports for programmatic API access

- **generator.lua** - AI commit message generation:
  - Handles both HTTP and ACP adapter types
  - Manages streaming responses from LLM
  - Creates prompts with optional commit history context
  - Cleans markdown formatting from LLM responses

- **git.lua** - Core Git operations wrapper:
  - Repository detection and validation
  - Diff generation with file filtering support
  - Commit history retrieval for context
  - Detects amend operations vs. normal commits

- **buffer.lua** - GitCommit buffer integration:
  - Auto-generation on `git commit` buffer enter
  - Configurable keymap for manual generation
  - Skip logic for `git commit --amend` operations

- **config.lua** - Centralized configuration with defaults
- **ui.lua** - Commit message display and editing interface
- **langs.lua** - Multi-language support for commit messages

**Tool Modules (tools/):**
- **git.lua** - Shared `GitTool` class with core Git command execution
  - All operations use `vim.fn.system()` for synchronous Git commands
  - Async operations use `vim.uv.spawn()` for non-blocking execution
  - Returns structured results: `success, output, user_msg, llm_msg`
  - Consistent response formatting with icons and XML tags

- **git_read.lua** - 16 read-only Git operations:
  - status, log, diff, branch, contributors, tags, etc.
  - Includes `generate_release_notes` for structured release notes
  - All operations are safe (no repository modifications)

- **git_edit.lua** - 17 write operations:
  - stage, unstage, commit, branch operations, push, merge, etc.
  - Requires user confirmation in chat interface
  - Includes safety checks and validation

- **ai_release_notes.lua** - AI-powered release note generation:
  - Analyzes commit history between tags
  - Supports multiple styles: detailed, concise, changelog, marketing
  - Uses smart prompts from `prompts/release_notes.lua`
  - Integrates with CodeCompanion's chat tool framework

## Key Development Patterns

### Tool Registration and Configuration
Tools are registered conditionally in `init.lua:setup_tools()` based on configuration flags:
- `enable_git_read` - Enable read-only operations
- `enable_git_edit` - Enable write operations
- `enable_git_bot` - Enable comprehensive Git assistant (requires both read/write)
- Each tool includes `auto_submit_errors` and `auto_submit_success` options

### Git Tool Response Format
All Git tool operations return a consistent 4-tuple:
```lua
return success, output, user_msg, llm_msg
```
- `success` (boolean) - Operation success/failure
- `output` (string) - Raw Git command output
- `user_msg` (string) - Formatted message with icons (✓, ✗, ℹ) for display
- `llm_msg` (string) - XML-tagged structured message for LLM processing

### Adapter Handling (HTTP vs ACP)
The `generator.lua` module supports two adapter types:
- **HTTP adapters** - Use `HTTPClient` with streaming chunks processed by `adapter.handlers.chat_output`
- **ACP adapters** - Use `ACPClient` with `session_prompt()` for message-based communication
- Schema mapping occurs before client creation for HTTP, but not for ACP
- Both paths handle streaming and accumulate responses before cleaning

### Async Operations
- Git operations use `vim.fn.system()` for simple blocking calls
- Async operations (push, background tasks) use `vim.uv.spawn()` with callbacks
- All async operations properly handle stdout/stderr pipes and cleanup

### Configuration Management
- Configuration is centralized in `config.lua` with comprehensive defaults
- User config is merged using `vim.tbl_deep_extend("force", default_opts, user_opts)`
- Config is passed to module setup functions during initialization
- Git module stores exclude patterns and commit history settings

### Error Handling
- Git operations return structured results with success/error states
- User-facing operations show notifications via `vim.notify`
- Tool operations can auto-submit results to LLM based on config
- Detailed error messages include context about what failed

### Commit History Context
When `use_commit_history = true`:
- Recent commits are retrieved and formatted for LLM context
- Helps maintain consistent commit message style across the project
- Number of commits controlled by `commit_history_count` setting

### GitCommit Buffer Detection
- `git.lua:is_amending()` detects `git commit --amend` operations
- Checks for `COMMIT_EDITMSG` buffer and presence of existing commit message
- Used to skip auto-generation when amending to preserve original message

## Important Implementation Details

### Slash Command Implementation
The `/gitcommit` slash command (in `init.lua`):
- Uses `vim.uv.spawn()` to run `git log` asynchronously
- Presents commit selection UI via `vim.ui.select()`
- Retrieves full commit content with `git show`
- Inserts commit into chat as context with `<git_commit>` tags

### AI Release Notes Tool
The `@ai_release_notes` tool follows CodeCompanion's tool protocol:
- `schema` - Defines parameters (from_tag, to_tag, style, etc.)
- `system_prompt` - Instructions for the AI
- `cmds` - Array of functions that return `{status, data}` structure
- `handlers` - Setup and cleanup lifecycle hooks
- `output` - Success/error handlers that call `chat:add_tool_output()`
- `opts` - Tool options like `requires_approval`

### Git Bot System Prompt
The `@git_bot` tool group combines git_read and git_edit with a comprehensive system prompt that:
- Emphasizes safety protocols (no force operations without confirmation)
- Follows workflow: read state → analyze → explain → execute
- Maintains best practices for commit history and branching
- Provides clear explanations before destructive operations

### Response Formatting
User messages use icons for visual clarity:
- ✓ - Success
- ✗ - Error
- ℹ - Information/empty result

LLM messages use XML tags for structured parsing:
- `<gitStatusTool>`, `<gitLogTool>`, etc.
- Consistent format: `<tag>success: output</tag>` or `<tag>fail: error</tag>`

## API Exports

The extension exports a comprehensive programmatic API through `init.lua` exports:
- `generate(lang, callback)` - Generate commit message
- `is_git_repo()` - Repository detection
- `get_staged_diff()` - Get staged changes
- `commit_changes(message)` - Commit with message
- `git_tool` - Object with all Git operations (status, log, diff, stage, commit, push, etc.)

## CodeCompanion Integration Points

### Tool Protocol
Tools must implement:
- `name` - Tool identifier
- `description` - What the tool does
- `schema` - JSON schema for parameters (optional)
- `cmds` - Array of command functions
- `output.success` and `output.error` - Result handlers

### Chat Context Management
- Use `chat:add_context(content, source, tag)` to add context
- Use `chat:add_tool_output(self, llm_msg, user_msg)` for tool results
- Source and tag parameters help categorize context

### Adapter Resolution
- Use `codecompanion_adapter.resolve(name, opts)` to get adapter instance
- Schema mapping: `adapter:map_schema_to_params(schema)` for HTTP adapters
- Role mapping: `adapter:map_roles(messages)` to convert message roles

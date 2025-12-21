local codecompanion_adapter = require("codecompanion.adapters")
local codecompanion_schema = require("codecompanion.schema")
local Debug = require("codecompanion._extensions.gitcommit.debug")

---@class CodeCompanion.GitCommit.Generator
local Generator = {}

--- @type string? Adapter name
local _adapter_name = nil
--- @type string? Model name
local _model_name = nil

local CONSTANTS = {
  STATUS_ERROR = "error",
  STATUS_SUCCESS = "success",
}

--- @param adapter string?  The adapter to use for generation
--- @param model string? The model of the adapter to use for generation
function Generator.setup(adapter, model)
  _adapter_name = adapter
  _model_name = model
end

---Create a client for both HTTP and ACP adapters
---@param adapter table The resolved adapter
---@return table|nil client The client instance
---@return string|nil error Error message if failed
local function create_client(adapter)
  if not adapter or not adapter.type then
    return nil, "Invalid adapter: missing type field"
  end

  if adapter.type == "http" then
    local HTTPClient = require("codecompanion.http")
    return HTTPClient.new({ adapter = adapter }), nil
  elseif adapter.type == "acp" then
    local ACPClient = require("codecompanion.acp")
    local client = ACPClient.new({ adapter = adapter })
    local ok = client:connect_and_initialize()
    if not ok then
      return nil, "Failed to connect and initialize ACP client"
    end
    return client, nil
  else
    return nil, "Unknown adapter type: " .. tostring(adapter.type)
  end
end

---Send request using HTTP client
---@param client table HTTP client
---@param adapter table Adapter instance
---@param payload table Request payload
---@param callback function Callback function
local function send_http_request(client, adapter, payload, callback)
  Debug.trace_enter("generator", "send_http_request", { adapter_name = adapter.name })

  -- Ensure callback is valid
  if type(callback) ~= "function" then
    error("send_http_request: callback must be a function, got " .. type(callback))
    return
  end

  local accumulated = ""
  local has_error = false

  -- Create a wrapper to ensure callback is only called once
  local callback_called = false
  local safe_callback = function(result, err)
    if callback_called then
      return
    end
    callback_called = true

    if type(callback) == "function" then
      callback(result, err)
    else
      vim.notify("Callback lost during HTTP request", vim.log.levels.ERROR)
    end
  end

  -- Prepare options for spinner events
  local request_opts = {
    adapter = {
      name = adapter.name or "unknown",
      formatted_name = adapter.formatted_name or adapter.name or "GitCommit",
      model = (adapter.schema and adapter.schema.model and adapter.schema.model.default) or "",
    },
    strategy = "gitcommit",
    silent = false,
  }

  -- Use async send to properly handle streaming responses
  client:send(
    payload,
    vim.tbl_extend("force", request_opts, {
      stream = true,
      on_chunk = function(chunk)
        Debug.checkpoint("http_chunk", "Received chunk")
        if chunk and chunk ~= "" then
          -- Use adapter's chat_output handler to process the chunk
          local result = adapter.handlers.chat_output(adapter, chunk)
          Debug.log("generator", "Processed chunk", {
            status = result and result.status,
            has_content = result and result.output and result.output.content ~= nil,
          })
          if result and result.status == CONSTANTS.STATUS_SUCCESS then
            local content = result.output and result.output.content
            if content and content ~= "" then
              accumulated = accumulated .. content
              Debug.log("generator", "Accumulated content", { length = #accumulated })
            end
          end
        end
      end,
      on_done = function()
        Debug.checkpoint("http_done", "Request completed")
        Debug.log("generator", "HTTP on_done", { has_error = has_error, accumulated_length = #accumulated })
        if not has_error then
          if accumulated ~= "" then
            local cleaned = Generator._clean_commit_message(accumulated)
            Debug.log("generator", "Cleaned message", { original_length = #accumulated, cleaned_length = #cleaned })
            safe_callback(cleaned, nil)
          else
            Debug.error("generator", "Generated content is empty after processing all chunks")
            safe_callback(nil, "Generated content is empty")
          end
        end
      end,
      on_error = function(err)
        Debug.checkpoint("http_error", "Request error")
        Debug.error("generator", "HTTP request error", err)
        has_error = true
        local error_msg = "HTTP request failed: " .. (err.message or vim.inspect(err))
        safe_callback(nil, error_msg)
      end,
    })
  )
end

---Send request using ACP client
---@param client table ACP client
---@param adapter table Adapter instance
---@param messages table Array of messages
---@param callback function Callback function
local function send_acp_request(client, adapter, messages, callback)
  Debug.trace_enter("generator", "send_acp_request", { adapter_name = adapter.name })

  local accumulated = ""
  local has_error = false

  -- Prepare options for spinner events
  local request_opts = {
    adapter = {
      name = adapter.name or "unknown",
      formatted_name = adapter.formatted_name or adapter.name or "GitCommit",
      type = "acp",
      model = nil,
    },
    strategy = "gitcommit",
    silent = false,
  }

  -- ACP expects messages to have _meta field
  -- Add it to make messages compatible with form_messages
  local formatted_messages = vim.tbl_map(function(msg)
    return vim.tbl_extend("force", msg, {
      _meta = {
        visible = true,
      },
    })
  end, messages)

  client
    :session_prompt(formatted_messages)
    :with_options(request_opts)
    :on_message_chunk(function(chunk)
      Debug.checkpoint("acp_chunk", "Received chunk")
      if chunk and chunk ~= "" then
        accumulated = accumulated .. chunk
        Debug.log("generator", "ACP accumulated", { length = #accumulated })
      end
    end)
    :on_complete(function(stop_reason)
      Debug.checkpoint("acp_complete", "Request completed")
      Debug.log(
        "generator",
        "ACP on_complete",
        { has_error = has_error, accumulated_length = #accumulated, stop_reason = stop_reason }
      )
      if not has_error and accumulated ~= "" then
        -- ACP responses are plain text, wrap in expected format
        local cleaned = Generator._clean_commit_message(accumulated)
        Debug.log("generator", "Cleaned message", { original_length = #accumulated, cleaned_length = #cleaned })
        callback(cleaned, nil)
      elseif not has_error then
        Debug.error("generator", "ACP returned empty response")
        callback(nil, "ACP returned empty response")
      end
    end)
    :on_error(function(error)
      Debug.checkpoint("acp_error", "Request error")
      Debug.error("generator", "ACP error", error)
      has_error = true
      callback(nil, "ACP error: " .. vim.inspect(error))
    end)
    :send()
end

---Clean commit message by removing markdown code blocks and extra formatting
---@param message string Raw message from LLM
---@return string cleaned_message The cleaned commit message
function Generator._clean_commit_message(message)
  local cleaned = vim.trim(message)

  -- Remove markdown code blocks (```...``` or ````...````)
  -- Match opening code fence with optional language identifier
  cleaned = cleaned:gsub("^```+%w*\n", "")
  -- Match closing code fence
  cleaned = cleaned:gsub("\n```+$", "")

  -- Trim again after removing code blocks
  cleaned = vim.trim(cleaned)

  return cleaned
end

---@param commit_history? string[] Array of recent commit messages for context (optional)
---@param issue_id? string Issue ID extracted from branch name (optional)
function Generator.generate_commit_message(diff, lang, commit_history, issue_id, callback)
  Debug.trace_enter("generator", "generate_commit_message", {
    diff_length = #diff,
    lang = lang,
    has_history = commit_history ~= nil,
    issue_id = issue_id,
  })

  -- Validate callback
  if type(callback) ~= "function" then
    error("Generator.generate_commit_message: callback must be a function, got " .. type(callback))
    return
  end

  -- 1. Resolve adapter
  Debug.log("generator", "Resolving adapter", { adapter_name = _adapter_name, model_name = _model_name })
  local adapter = codecompanion_adapter.resolve(_adapter_name, {
    model = _model_name,
  })
  if not adapter then
    Debug.error("generator", "Failed to resolve adapter", { adapter_name = _adapter_name })
    return callback(nil, "Failed to resolve adapter: " .. tostring(_adapter_name))
  end
  Debug.log("generator", "Adapter resolved", { type = adapter.type, name = adapter.name })

  -- Validate adapter type
  if not adapter.type or (adapter.type ~= "http" and adapter.type ~= "acp") then
    Debug.error("generator", "Invalid adapter type", { type = adapter.type })
    return callback(nil, "Invalid or unsupported adapter type: " .. tostring(adapter.type))
  end

  -- 2. Create prompt
  local prompt = Generator._create_prompt(diff, lang, commit_history, issue_id)
  Debug.log("generator", "Created prompt", { length = #prompt })

  -- 3. Prepare messages
  local messages = {
    { role = "user", content = prompt },
  }

  -- 4. Map schema for HTTP adapter (must be done before client creation)
  if adapter.type == "http" then
    local schema_opts = {}
    if _model_name then
      schema_opts.model = _model_name
    end
    adapter = adapter:map_schema_to_params(codecompanion_schema.get_default(adapter, schema_opts))
  end

  -- 5. Create client (after potential schema mapping for HTTP)
  Debug.log("generator", "Creating client", { adapter_type = adapter.type })
  local client, err = create_client(adapter)
  if not client then
    Debug.error("generator", "Failed to create client", err)
    return callback(nil, err)
  end
  Debug.log("generator", "Client created successfully")

  -- 6. Send request based on adapter type
  Debug.log("generator", "Sending request", { adapter_type = adapter.type })
  if adapter.type == "http" then
    -- Prepare HTTP payload
    local payload = {
      messages = adapter:map_roles(messages),
    }

    send_http_request(client, adapter, payload, callback)
  elseif adapter.type == "acp" then
    send_acp_request(client, adapter, messages, function(result, error)
      -- Disconnect after request completes
      pcall(function()
        client:disconnect()
      end)
      callback(result, error)
    end)
  end
end

---Create prompt for commit message generation
---@param diff string The git diff to include in prompt
---@param commit_history? string[] Recent commit messages for context (optional)
function Generator._base_prompt(diff, lang, commit_history)
  -- Build history context section
  local history_context = ""
  if commit_history and #commit_history > 0 then
    history_context = "\nRECENT COMMIT HISTORY (for style reference):\n"
    for i, commit_msg in ipairs(commit_history) do
      history_context = history_context .. string.format("%d. %s\n", i, commit_msg)
    end
    history_context = history_context
      .. "\nAnalyze commit history to understand project style, tone, and format patterns. Use this for consistency.\n"
  end

  return string.format(
    [[You are a commit message generator. Generate exactly ONE Conventional Commit message for the provided git diff.%s

FORMAT:
type(scope): specific description of WHAT changed

[Optional body - only for non-obvious changes]

Allowed types: feat, fix, docs, style, refactor, perf, test, chore
Language: %s

CRITICAL RULES:
1. Respond with ONLY the commit message - no markdown blocks, no explanations
2. Description must state WHAT was done, not WHY or the effect
3. AVOID vague verbs: "update", "improve", "clarify", "adjust", "enhance", "fix issues"
   USE specific verbs: "add", "remove", "rename", "move", "replace", "extract", "inline"
4. Subject line under 50 chars, body lines under 72 chars
5. Body is OPTIONAL - omit if subject is self-explanatory

BAD (vague):
- refactor(api): improve error handling
- fix(auth): update login logic
- chore(deps): update dependencies

GOOD (specific):
- refactor(api): replace try-catch with Result type
- fix(auth): check token expiry before API call
- chore(deps): bump axios from 0.21 to 1.6

EXAMPLES:

docs(readme): add installation section

refactor(api): rename getUserData to fetchUser

feat(auth): add OAuth2 token refresh flow

- Store refresh token in secure storage
- Auto-refresh 5 min before expiry

```diff
%s
```]],
    history_context,
    lang or "English",
    diff
  )
end

function Generator._issue_id_prompt(issue_id)
  local issue_id_context = ""
  if issue_id and issue_id ~= "" then
    issue_id_context = string.format(
      [[

IMPORTANT: Issue ID Prefix Required
Please prefix the summary line with the following issue ID: %s
DO NOT include conventional commit type (feat, fix, chore, etc.) when using the issue ID prefix.

Format: %s: brief description

Examples:
%s: add OAuth2 integration
%s: resolve data validation issues
%s: update documentation]],
      issue_id,
      issue_id,
      issue_id,
      issue_id,
      issue_id
    )
  end

  return issue_id_context
end

---Create prompt for commit message generation
---@param diff string The git diff to include in prompt
---@param lang string Language for the commit message
---@param commit_history? string[] Recent commit messages for context (optional)
---@param issue_id? string Issue ID to prefix the commit message (optional)
function Generator._create_prompt(diff, lang, commit_history, issue_id)
  local base = Generator._base_prompt(diff, lang, commit_history)
  local issue_id_section = Generator._issue_id_prompt(issue_id)

  if issue_id_section ~= "" then
    base = base .. "\n\n" .. issue_id_section
  end

  return base
end

return Generator

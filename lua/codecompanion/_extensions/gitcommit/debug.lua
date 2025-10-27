---@class CodeCompanion.GitCommit.Debug
local Debug = {}

-- Set to true to enable debug logging
-- You can enable this by setting:
-- require("codecompanion._extensions.gitcommit.debug").enabled = true
Debug.enabled = false

-- Log file path (nil means use vim.notify only)
Debug.log_file = nil

---Log a debug message
---@param category string Category/module name (e.g., "generator", "buffer")
---@param message string Debug message
---@param data? any Optional data to inspect
function Debug.log(category, message, data)
  if not Debug.enabled then
    return
  end

  local timestamp = os.date("%Y-%m-%d %H:%M:%S")
  local log_msg = string.format("[%s] [%s] %s", timestamp, category, message)

  if data ~= nil then
    log_msg = log_msg .. "\n" .. vim.inspect(data)
  end

  -- Always log to vim.notify when debug is enabled
  vim.notify(log_msg, vim.log.levels.DEBUG)

  -- Optionally log to file
  if Debug.log_file then
    local file = io.open(Debug.log_file, "a")
    if file then
      file:write(log_msg .. "\n")
      file:close()
    end
  end
end

---Log error with context
---@param category string Category/module name
---@param message string Error message
---@param error any Error data
function Debug.error(category, message, error)
  if not Debug.enabled then
    return
  end

  Debug.log(category, "ERROR: " .. message, error)
end

---Trace function entry
---@param category string Category/module name
---@param func_name string Function name
---@param args? any Function arguments
function Debug.trace_enter(category, func_name, args)
  if not Debug.enabled then
    return
  end

  Debug.log(category, "→ ENTER: " .. func_name, args)
end

---Trace function exit
---@param category string Category/module name
---@param func_name string Function name
---@param result? any Return value
function Debug.trace_exit(category, func_name, result)
  if not Debug.enabled then
    return
  end

  Debug.log(category, "← EXIT: " .. func_name, result)
end

---Create a wrapper function that traces entry/exit
---@param category string Category name
---@param func_name string Function name
---@param func function Function to wrap
---@return function wrapped Wrapped function with tracing
function Debug.trace_function(category, func_name, func)
  if not Debug.enabled then
    return func
  end

  return function(...)
    local args = { ... }
    Debug.trace_enter(category, func_name, args)

    local results = { pcall(func, ...) }
    local success = table.remove(results, 1)

    if success then
      Debug.trace_exit(category, func_name, results)
      return unpack(results)
    else
      Debug.error(category, func_name .. " failed", results[1])
      error(results[1])
    end
  end
end

---Start a checkpoint (for tracking async operations)
---@param checkpoint_id string Unique identifier for this checkpoint
---@param message string Description
function Debug.checkpoint(checkpoint_id, message)
  if not Debug.enabled then
    return
  end

  Debug.log("checkpoint", checkpoint_id .. ": " .. message)
end

return Debug

# Troubleshooting Guide - GitCommit Extension

## Issue: AI-Generated Commit Messages Not Showing in Editor

If you're experiencing issues where the AI generates commit messages but they don't appear in the gitcommit editor, this guide will help you diagnose and fix the problem.

---

## Quick Diagnostic Steps

### 1. Enable Debug Logging

Add this to your Neovim configuration **before** loading the extension:

```lua
-- Enable debug logging
require("codecompanion._extensions.gitcommit.debug").enabled = true

-- Optional: log to a file for analysis
require("codecompanion._extensions.gitcommit.debug").log_file = "/tmp/gitcommit-debug.log"
```

Then reproduce the issue and check the debug output.

### 2. Check for Common Issues

Run through this checklist:

- [ ] Are you getting the "Generating commit message..." notification?
- [ ] Do you see any error messages in `:messages`?
- [ ] Is the gitcommit buffer still open when generation completes?
- [ ] Did you cancel the language selection prompt?
- [ ] Are you using `git commit --amend`? (auto-generation is disabled by default for amend)

---

## Common Failure Scenarios

### Scenario 1: Silent Language Selection Cancellation

**Symptoms:**
- "Generating commit message..." notification never appears
- No error messages
- Nothing happens after opening git commit

**Cause:** User pressed `<Esc>` or cancelled the language selection prompt.

**Fix:** This is working as intended. When debug logging is enabled, you'll see:
```
[buffer] User cancelled language selection
```

And now a warning notification appears: "Commit message generation cancelled"

---

### Scenario 2: Buffer Becomes Invalid

**Symptoms:**
- "Generating commit message..." appears
- Error: "Buffer is no longer valid"
- Message was generated but can't be inserted

**Cause:** Git commit buffer was closed before AI finished generating the message.

**Debug logs show:**
```
[buffer] → ENTER: _generate_and_insert_commit_message
[generator] Adapter resolved
...
[buffer_callback] Generator callback invoked
[buffer] ERROR: Buffer no longer valid
```

**Fix:**
- Wait for generation to complete before closing the editor
- Use a faster model if generation is too slow
- Reduce `commit_history_count` to speed up generation

---

### Scenario 3: Adapter Returns Empty Response

**Symptoms:**
- "Generating commit message..." appears
- Error: "Generated content is empty" or "Failed to generate commit message"
- AI responds but content extraction fails

**Debug logs show:**
```
[generator] HTTP on_done: accumulated_length = 0
```
Or for chunks:
```
[http_chunk] Received chunk
[generator] Processed chunk: has_content = false
```

**Possible Causes:**
1. **Adapter handler not extracting content correctly** - The `adapter.handlers.chat_output` may not be compatible
2. **Model returns only code blocks** - The cleaning function removes them but nothing is left
3. **Network/API errors** - Response is malformed

**Fix:**
- Check which adapter you're using
- Try a different adapter (e.g., switch from HTTP to ACP or vice versa)
- Check `:CodeCompanionChat` works normally with your adapter
- Review the raw accumulated content in debug logs to see what the LLM actually returned

---

### Scenario 4: HTTP Adapter Streaming Issues

**Symptoms:**
- Generation takes a long time or hangs
- No error messages
- `on_done` callback never fires

**Debug logs show:**
```
[generator] Sending request: adapter_type = http
[http_chunk] Received chunk
...
(no http_done checkpoint)
```

**Possible Causes:**
- Adapter streaming not completing properly
- Network timeout
- Missing `on_done` event from HTTP client

**Fix:**
- Check network connectivity
- Try a different model or adapter
- Check CodeCompanion's HTTP client configuration
- Review CodeCompanion's `:messages` for underlying errors

---

### Scenario 5: ACP Adapter Connection Issues

**Symptoms:**
- Error: "Failed to create client"
- Error: "Failed to connect and initialize ACP client"

**Debug logs show:**
```
[generator] Creating client: adapter_type = acp
[generator] ERROR: Failed to create client
```

**Fix:**
- Ensure ACP server is running
- Check ACP server configuration
- Verify network connectivity to ACP server
- Review ACP server logs

---

## Advanced Debugging

### Trace the Full Flow

With debug logging enabled, you should see this sequence for a successful generation:

```
1. [buffer] → ENTER: _generate_and_insert_commit_message
2. [buffer] Got diff: has_diff = true
3. [buffer] Language selected: lang = "English"
4. [buffer] Starting generation
5. [generator] → ENTER: generate_commit_message
6. [generator] Resolving adapter
7. [generator] Adapter resolved: type = "http", name = "anthropic"
8. [generator] Creating client
9. [generator] Client created successfully
10. [generator] Sending request
11. [http_chunk] Received chunk (repeated)
12. [generator] Accumulated content: length = 157
13. [http_done] Request completed
14. [generator] Cleaned message: cleaned_length = 145
15. [buffer_callback] Generator callback invoked
16. [buffer] Calling _insert_commit_message
17. [buffer] → ENTER: _insert_commit_message
18. [buffer] Successfully inserted commit message
```

### Check Where It Breaks

If the flow stops at any point, that indicates where the issue is:

- **Stops at step 2**: No staged changes, or git diff failed
- **Stops at step 3**: Language selection cancelled
- **Stops at step 7**: Adapter not found or invalid configuration
- **Stops at step 9**: Client creation failed
- **Stops at step 11**: Network/API issue, no response chunks
- **Stops at step 14**: Empty response from LLM
- **Stops at step 16**: Buffer became invalid

---

## Configuration Tweaks

### Disable Auto-generation on Amend

If you want auto-generation even during `git commit --amend`:

```lua
require("codecompanion").setup({
  extensions = {
    gitcommit = {
      buffer = {
        skip_auto_generate_on_amend = false,
      },
    },
  },
})
```

### Adjust Timing for Slow Systems

If the buffer isn't stable when auto-generation triggers:

```lua
require("codecompanion").setup({
  extensions = {
    gitcommit = {
      buffer = {
        auto_generate_delay = 200,  -- Increase from default 100ms
        window_stability_delay = 500,  -- Increase from default 300ms
      },
    },
  },
})
```

### Change Adapter or Model

Try a different adapter if the current one has issues:

```lua
require("codecompanion").setup({
  extensions = {
    gitcommit = {
      adapter = "openai",  -- Instead of default
      model = "gpt-4",  -- Faster models may help
    },
  },
})
```

---

## Still Having Issues?

### Collect Debug Information

1. Enable debug logging with file output:
```lua
local debug = require("codecompanion._extensions.gitcommit.debug")
debug.enabled = true
debug.log_file = "/tmp/gitcommit-debug.log"
```

2. Reproduce the issue

3. Check both:
   - Neovim messages: `:messages`
   - Debug log file: `cat /tmp/gitcommit-debug.log`

4. Look for the patterns described in the "Trace the Full Flow" section

### Report the Issue

When reporting issues, please include:

1. **Configuration**: Your CodeCompanion and gitcommit extension setup
2. **Adapter**: Which adapter and model you're using
3. **Debug logs**: The relevant portions showing where the flow breaks
4. **Git command**: What git command you ran (e.g., `git commit`, `git commit --amend`, `git commit -v`)
5. **Neovim version**: Output of `:version`
6. **CodeCompanion version**: Check your plugin manager

---

## Prevention Tips

1. **Keep CodeCompanion Updated**: Ensure you're using the latest version
2. **Test Adapter First**: Verify your adapter works in `:CodeCompanionChat` before using gitcommit
3. **Use Stable Models**: Experimental models may have unpredictable output formats
4. **Monitor Performance**: Slower models may cause timeout issues
5. **Check Git State**: Ensure you have staged changes before committing

---

## Technical Details

### How It Works

The flow from generation to display:

1. **Buffer Integration** (`buffer.lua`):
   - Detects gitcommit filetype
   - Checks for staged changes
   - Prompts for language selection
   - Calls generator with callback

2. **Message Generation** (`generator.lua`):
   - Resolves adapter
   - Creates prompt with diff
   - Sends async request (HTTP or ACP)
   - Accumulates streamed response
   - Cleans markdown formatting
   - Calls callback with result

3. **Message Insertion** (`buffer.lua`):
   - Validates buffer still exists
   - Finds insertion point (before comments)
   - Inserts message lines
   - Moves cursor to start

### Critical Async Points

The callback chain is asynchronous, which means:
- Buffer might close before callback executes
- Network delays can cause long waits
- Errors in streaming can prevent callback

This is why debug logging is crucial - it shows exactly where async operations complete or fail.

---

## Quick Reference: Debug Module API

```lua
local Debug = require("codecompanion._extensions.gitcommit.debug")

-- Enable/disable logging
Debug.enabled = true/false

-- Set log file (optional)
Debug.log_file = "/path/to/log.txt"

-- Manual logging (when enabled)
Debug.log("category", "message", optional_data)
Debug.error("category", "error message", error_object)
Debug.checkpoint("id", "description")
```

All debug output is automatically prefixed with timestamps and categories for easy analysis.

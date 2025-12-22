local M = {}

--- Create issue ID prompt section
---@param issue_id string? Issue ID to prefix the commit message (optional)
---@return string issue_id_context The issue ID prompt section
function M.generate_with_issue_id_prompt(issue_id)
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

return M

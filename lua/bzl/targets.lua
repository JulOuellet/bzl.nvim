local M = {}

---@class bzl.Target
---@field kind string rule kind, e.g. "sh_test"
---@field label string full label, e.g. "//lib:greetings"

---@type table<string, bzl.Target[]> target list per workspace root
local cache = {}

---Parse `bazel query --output=label_kind` output into targets.
---Pure function: raw stdout in, targets out. Lines that are not
---`<kind> rule <label>` (source files, progress noise, ...) are skipped.
---@param output string
---@return bzl.Target[]
function M.parse(output)
	local targets = {}
	for line in output:gmatch("[^\r\n]+") do
		local kind, label = line:match("^(%S+) rule (%S+)$")
		if kind then
			table.insert(targets, { kind = kind, label = label })
		end
	end
	return targets
end

---List all targets in the current workspace, from cache when warm.
---Errors are reported via vim.notify; `on_done` then receives nil, so
---callers can always rely on being called exactly once.
---@param on_done fun(targets: bzl.Target[]|nil)
---@param opts { refresh: boolean }|nil
function M.list(on_done, opts)
	local cli = require("bzl.cli")

	local root = cli.workspace_root()
	if root and cache[root] and not (opts and opts.refresh) then
		on_done(cache[root])
		return
	end

	local started = cli.run({ "query", "//...", "--output=label_kind" }, function(result)
		if result.code ~= 0 then
			vim.notify("bzl.nvim: bazel query failed:\n" .. (result.stderr or ""), vim.log.levels.ERROR)
			on_done(nil)
			return
		end
		local targets = M.parse(result.stdout or "")
		cache[root] = targets
		on_done(targets)
	end)
	if not started then
		on_done(nil)
	end
end

---Drop all cached target lists (e.g. after BUILD file edits).
function M.refresh()
	cache = {}
end

return M

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

---Parse a workspace-local label into package and target name.
---External labels ("@repo//...") are not supported and yield nil.
---Pure function.
---@param label string e.g. "//lib:greetings"
---@return { package: string, name: string }|nil
function M.parse_label(label)
	local pkg, name = label:match("^//([^:]*):([^:/]+)$")
	if not pkg then
		return nil
	end
	return { package = pkg, name = name }
end

---Resolve a label to the BUILD file defining it and, when found, to
---the line of its `name = "..."` attribute.
---@param label string
---@param root string workspace root (absolute path)
---@return { file: string, lnum: integer|nil }|nil
function M.location(label, root)
	local parsed = M.parse_label(label)
	if not parsed then
		return nil
	end
	local dir = parsed.package == "" and root or (root .. "/" .. parsed.package)
	for _, build_name in ipairs({ "BUILD.bazel", "BUILD" }) do
		local file = dir .. "/" .. build_name
		if vim.uv.fs_stat(file) then
			local pattern = 'name%s*=%s*"' .. vim.pesc(parsed.name) .. '"'
			local lnum = 0
			for line in io.lines(file) do
				lnum = lnum + 1
				if line:match(pattern) then
					return { file = file, lnum = lnum }
				end
			end
			return { file = file }
		end
	end
	return nil
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

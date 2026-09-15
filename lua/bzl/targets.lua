local M = {}

---@class bzl.Target
---@field kind string rule kind, e.g. "sh_test"
---@field label string full label, e.g. "//lib:greetings"

---@type table<string, bzl.Target[]> target list per workspace root
local cache = {}
local pending = {}

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

---Package of a file: the directory of the nearest BUILD file at or
---above it, relative to the workspace root.
---@param path string absolute file path
---@param root string workspace root (absolute path)
---@return string|nil package "" for the root package, nil outside one
function M.package_of(path, root)
	local build = vim.fs.find({ "BUILD.bazel", "BUILD" }, {
		path = vim.fs.dirname(path),
		upward = true,
		stop = vim.fs.dirname(root),
	})[1]
	if not build then
		return nil
	end
	local dir = vim.fs.dirname(build)
	if dir == root then
		return ""
	end
	if dir:sub(1, #root + 1) ~= root .. "/" then
		return nil -- BUILD file found above the workspace root
	end
	return dir:sub(#root + 2)
end

---Directory scope of the file's "project": the nearest ancestor (up to
---the workspace root) containing a *.bazelproject view file, falling
---back to the file's package when no view files exist.
---@param path string absolute file path
---@param root string workspace root (absolute path)
---@return string|nil workspace-relative dir, "" for the root, nil outside
function M.project_of(path, root)
	local dir = vim.fs.dirname(path)
	while dir == root or dir:sub(1, #root + 1) == root .. "/" do
		local handle = vim.uv.fs_scandir(dir)
		while handle do
			local name = vim.uv.fs_scandir_next(handle)
			if not name then
				break
			end
			if name:match("%.bazelproject$") then
				return dir == root and "" or dir:sub(#root + 2)
			end
		end
		if dir == root then
			break
		end
		dir = vim.fs.dirname(dir)
	end
	return M.package_of(path, root)
end

---List all targets in a workspace, from cache when warm.
---Errors are reported via vim.notify; `on_done` then receives nil, so
---callers can always rely on being called exactly once.
---@param root string|nil workspace root
---@param on_done fun(targets: bzl.Target[]|nil)
---@param opts { refresh: boolean }|nil
function M.list(root, on_done, opts)
	opts = opts or {}
	local cli = require("bzl.cli")
	local config = opts.config or require("bzl.config").get(root)
	local scope = opts.scope or { "//..." }
	local key = vim.inspect({ root, config.bazel_cmd, config.startup_args, config.command_args.query, scope })
	if cache[key] and not opts.refresh then
		local entry = cache[key]
		vim.schedule(function()
			on_done(cache[key] == entry and entry.targets or nil)
		end)
		return
	end
	if pending[key] then
		table.insert(pending[key].callbacks, on_done)
		return
	end
	local request = { root = root, callbacks = { on_done } }
	pending[key] = request
	request.handle = cli.run(root, { "query", M.expression(scope), "--output=label_kind" }, function(result)
		if pending[key] ~= request then
			return
		end
		pending[key] = nil
		local targets
		if result.code ~= 0 then
			if result.status ~= "cancelled" then
				vim.notify("bzl.nvim: bazel query failed:\n" .. (result.stderr or ""), vim.log.levels.ERROR)
			end
		else
			targets = M.parse(result.stdout or "")
			cache[key] = { root = root, targets = targets }
		end
		for _, callback in ipairs(request.callbacks) do
			callback(targets)
		end
	end, { config = config, timeout = config.sync.query_timeout })
	return request.handle
end

function M.expression(scope)
	return "set("
		.. table.concat(
			vim.tbl_map(function(label)
				return string.format("%q", label)
			end, scope),
			" "
		)
		.. ")"
end

---Drop all cached target lists (e.g. after BUILD file edits).
function M.refresh(root)
	for key, entry in pairs(cache) do
		if not root or entry.root == root then
			cache[key] = nil
		end
	end
	for key, request in pairs(pending) do
		if not root or request.root == root then
			pending[key] = nil
			if request.handle and request.handle.cancel then
				request.handle.cancel()
			end
			for _, callback in ipairs(request.callbacks) do
				vim.schedule(function()
					callback(nil)
				end)
			end
		end
	end
end

return M

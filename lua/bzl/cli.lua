local M = {}

local ROOT_MARKERS = { "MODULE.bazel", "WORKSPACE", "WORKSPACE.bazel" }

---Find the bazel workspace root: the nearest ancestor of the current buffer
---containing a workspace marker file.
---@param buf integer|nil buffer handle, defaults to the current buffer
---@return string|nil
function M.workspace_root(buf)
	return vim.fs.root(buf or 0, ROOT_MARKERS)
end

---@class bzl.CliResult
---@field code integer exit code
---@field stdout string|nil
---@field stderr string|nil

---Run bazel asynchronously from the workspace root.
---`on_done` always runs on the main loop, so it may use any nvim API.
---@param args string[] bazel arguments, e.g. { "query", "//..." }
---@param on_done fun(result: bzl.CliResult)
---@return boolean started false if no workspace or the binary could not be spawned
function M.run(args, on_done)
	local root = M.workspace_root()
	if not root then
		vim.notify(
			"bzl.nvim: no bazel workspace found (no MODULE.bazel or WORKSPACE above this file)",
			vim.log.levels.ERROR
		)
		return false
	end

	local cmd = { require("bzl.config").get().bazel_cmd }
	vim.list_extend(cmd, args)

	local ok, err = pcall(vim.system, cmd, { cwd = root, text = true }, vim.schedule_wrap(on_done))
	if not ok then
		vim.notify(("bzl.nvim: could not run %q: %s"):format(cmd[1], err), vim.log.levels.ERROR)
		return false
	end
	return true
end

return M

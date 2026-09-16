local M = {}

local ROOT_MARKERS = { "MODULE.bazel", "WORKSPACE", "WORKSPACE.bazel" }

---Find the bazel workspace root: the nearest ancestor of the current buffer
---containing a workspace marker file.
---@param buf integer|string|nil buffer handle or path, defaults to the current buffer
---@return string|nil
function M.workspace_root(buf)
	local root = vim.fs.root(buf or 0, ROOT_MARKERS)
	return root and (vim.uv.fs_realpath(root) or root)
end

---Use the same Bazel configuration for analysis, builds, and the runner.
function M.command(args, config)
	config = config or require("bzl.config").get()
	local cmd = { config.bazel_cmd }
	vim.list_extend(cmd, config.startup_flags)
	cmd[#cmd + 1] = args[1]
	if vim.tbl_contains({ "build", "run", "test", "cquery", "info" }, args[1]) then
		vim.list_extend(cmd, config.build_flags)
	end
	vim.list_extend(cmd, vim.list_slice(args, 2))
	return cmd
end

---@class bzl.CliResult
---@field code integer exit code
---@field stdout string|nil
---@field stderr string|nil

---Run bazel asynchronously from a workspace root.
---`on_done` always runs on the main loop, so it may use any nvim API.
---@param root string|nil workspace root
---@param args string[] bazel arguments, e.g. { "query", "//..." }
---@param on_done fun(result: bzl.CliResult)
---@param config table|nil configuration snapshot, defaults to current setup
---@return boolean started false if no workspace or the binary could not be spawned
function M.run(root, args, on_done, config)
	if not root then
		vim.notify(
			"bzl.nvim: no bazel workspace found (no MODULE.bazel or WORKSPACE above this file)",
			vim.log.levels.ERROR
		)
		return false
	end

	local cmd = M.command(args, config)

	local ok, err = pcall(vim.system, cmd, { cwd = root, text = true }, vim.schedule_wrap(on_done))
	if not ok then
		vim.notify(("bzl.nvim: could not run %q: %s"):format(cmd[1], err), vim.log.levels.ERROR)
		return false
	end
	return true
end

return M

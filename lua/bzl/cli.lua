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

---Run a process, optionally streaming stderr while retaining it in the result.
---Both callbacks run on the main loop; on_stderr(nil) marks end of output.
function M.system(cmd, opts, on_done, on_stderr)
	opts = vim.tbl_extend("force", { text = true }, opts)
	local chunks = {}
	if on_stderr then
		opts.stderr = function(err, data)
			local chunk = err or data
			if chunk then
				chunks[#chunks + 1] = chunk
				vim.schedule(function()
					on_stderr(chunk)
				end)
			end
		end
	end
	return vim.system(
		cmd,
		opts,
		vim.schedule_wrap(function(result)
			if on_stderr then
				result.stderr = table.concat(chunks)
				if opts.text then
					result.stderr = result.stderr:gsub("\r\n", "\n")
				end
				on_stderr(nil)
			end
			on_done(result)
		end)
	)
end

---Run bazel asynchronously from a workspace root.
---`on_done` always runs on the main loop, so it may use any nvim API.
---@param root string|nil workspace root
---@param args string[] bazel arguments, e.g. { "query", "//..." }
---@param on_done fun(result: bzl.CliResult)
---@param config table|nil configuration snapshot, defaults to current setup
---@param on_stderr fun(data: string|nil)|nil live stderr, followed by nil before on_done
---@return boolean started false if no workspace or the binary could not be spawned
function M.run(root, args, on_done, config, on_stderr)
	if not root then
		vim.notify(
			"bzl.nvim: no bazel workspace found (no MODULE.bazel or WORKSPACE above this file)",
			vim.log.levels.ERROR
		)
		return false
	end

	local cmd = M.command(args, config)

	local ok, err = pcall(M.system, cmd, { cwd = root }, on_done, on_stderr)
	if not ok then
		vim.notify(("bzl.nvim: could not run %q: %s"):format(cmd[1], err), vim.log.levels.ERROR)
		return false
	end
	return true
end

return M

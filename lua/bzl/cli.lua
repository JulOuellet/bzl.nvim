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
---@field status string exit|failed|cancelled|timeout

---Run bazel asynchronously from a workspace root.
---`on_done` always runs on the main loop, so it may use any nvim API.
---@param root string|nil workspace root
---@param args string[] bazel arguments, e.g. { "query", "//..." }
---@param on_done fun(result: bzl.CliResult)
---@param opts? { config?: table, timeout?: integer }
---@return table handle includes cancel(); callback runs exactly once even on spawn failure
function M.run(root, args, on_done, opts)
	opts = opts or {}
	local process, finished, cancelled
	local handle = {}
	local function finish(result)
		if finished then
			return
		end
		finished = true
		result.stdout, result.stderr = result.stdout or "", result.stderr or ""
		vim.schedule(function()
			on_done(result)
		end)
	end
	function handle.cancel()
		if finished or cancelled then
			return
		end
		cancelled = true
		if process then
			pcall(process.kill, process, 15)
			vim.defer_fn(function()
				if not finished then
					pcall(process.kill, process, 9)
				end
			end, 1000)
		else
			finish({ code = -1, status = "cancelled", stderr = "cancelled" })
		end
	end
	if not root then
		finish({
			code = -1,
			status = "failed",
			stderr = "no bazel workspace found (no MODULE.bazel or WORKSPACE above this file)",
		})
		return handle
	end
	local ok, result = pcall(vim.system, M.command(root, args, opts.config), {
		cwd = root,
		text = true,
		timeout = opts.timeout and opts.timeout > 0 and opts.timeout or nil,
	}, function(output)
		output.status = cancelled and "cancelled" or (output.code == 124 and "timeout" or "exit")
		finish(output)
	end)
	if ok then
		process = result
	else
		finish({ code = -1, status = "failed", stderr = tostring(result) })
	end
	return handle
end

---Build argv without shell interpolation. Startup flags precede the verb.
function M.command(root, args, config)
	config = config or require("bzl.config").get(root)
	local cmd = { config.bazel_cmd }
	vim.list_extend(cmd, config.startup_args)
	cmd[#cmd + 1] = args[1]
	vim.list_extend(cmd, config.command_args[args[1]] or {})
	vim.list_extend(cmd, vim.list_slice(args, 2))
	return cmd
end

return M

local M = {}

---Optional. The plugin works with defaults if this is never called.
---@param opts table|nil
function M.setup(opts)
	require("bzl.config").setup(opts)
end

function M.hello()
	local config = require("bzl.config").get()
	local msg = ("bzl.nvim is alive (bazel_cmd: %s)"):format(config.bazel_cmd)
	vim.notify(msg, vim.log.levels.INFO, { title = "bzl.nvim" })
end

function M.targets()
	require("bzl.picker").targets()
end

function M.here()
	require("bzl.picker").here()
end

function M.rerun()
	require("bzl.runner").rerun()
end

---Force a fresh target query, like the sync button of the IntelliJ
---bazel plugin. Reports progress and the resulting target count.
function M.sync()
	vim.notify("bzl.nvim: syncing targets...", vim.log.levels.INFO)
	local start = vim.uv.hrtime()
	require("bzl.targets").list(function(targets)
		if not targets then
			return -- failure already notified
		end
		require("bzl.python").sync(function(python)
			local ms = math.floor((vim.uv.hrtime() - start) / 1e6)
			local msg = ("bzl.nvim: synced %d targets in %d ms"):format(#targets, ms)
			if python then
				msg = msg .. (", %d python paths -> %d clients"):format(python.paths, python.clients)
			end
			vim.notify(msg, vim.log.levels.INFO)
		end)
	end, { refresh = true })
end

M.subcommands = {
	hello = M.hello,
	targets = M.targets,
	here = M.here,
	rerun = M.rerun,
	sync = M.sync,
}

---Entry point for the :Bzl user command.
---@param fargs string[]
function M.cmd(fargs)
	local name = fargs[1] or "hello"
	local subcommand = M.subcommands[name]
	if not subcommand then
		vim.notify(("bzl.nvim: unknown subcommand %q"):format(name), vim.log.levels.ERROR)
		return
	end
	subcommand()
end

return M

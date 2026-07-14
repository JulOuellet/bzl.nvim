local M = {}

---Optional. The plugin works with defaults if this is never called.
---@param opts table|nil
function M.setup(opts)
	require("bzl.config").setup(opts)
end

function M.targets(...)
	require("bzl.picker").targets(...)
end

function M.tree(...)
	require("bzl.picker").tree(...)
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
	targets = M.targets,
	tree = M.tree,
	rerun = M.rerun,
	sync = M.sync,
}

---Entry point for the :Bzl user command. Arguments after the
---subcommand name are forwarded to it.
---@param fargs string[]
function M.cmd(fargs)
	if #fargs == 0 then
		vim.notify(
			"bzl.nvim usage: Bzl targets|tree [testable|runnable] [here] | Bzl sync | Bzl rerun",
			vim.log.levels.INFO
		)
		return
	end
	local subcommand = M.subcommands[fargs[1]]
	if not subcommand then
		vim.notify(("bzl.nvim: unknown subcommand %q"):format(fargs[1]), vim.log.levels.ERROR)
		return
	end
	subcommand(unpack(fargs, 2))
end

return M

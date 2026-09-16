local M = {}
local syncing = {}

---Optional. The plugin works with defaults if this is never called.
---@param opts table|nil
function M.setup(opts)
	require("bzl.config").setup(opts)
end

function M.targets(...)
	require("bzl.picker").targets(...)
end

---Refresh targets and synchronize the configured Python project.
function M.sync()
	local root = require("bzl.cli").workspace_root()
	if root and syncing[root] then
		vim.notify("bzl.nvim: sync already running for " .. root, vim.log.levels.WARN)
		return
	end
	if root then
		syncing[root] = true
	end
	vim.notify("bzl.nvim: syncing targets...", vim.log.levels.INFO)
	local start = vim.uv.hrtime()
	require("bzl.targets").list(root, function(targets)
		if not targets then
			if root then
				syncing[root] = nil
			end
			return -- failure already notified
		end
		require("bzl.python").sync(root, function(python)
			syncing[root] = nil
			if not python then
				return -- Python sync reports failures and retains the old model
			end
			local ms = math.floor((vim.uv.hrtime() - start) / 1e6)
			local msg = ("bzl.nvim: synced %d targets in %d ms"):format(#targets, ms)
			msg = msg .. (", %d python paths -> %d clients"):format(python.paths, python.clients)
			vim.notify(msg, vim.log.levels.INFO)
		end, targets)
	end, { refresh = true })
end

M.subcommands = {
	targets = M.targets,
	sync = M.sync,
}

---Entry point for the :Bzl user command. Arguments after the
---subcommand name are forwarded to it.
---@param fargs string[]
function M.cmd(fargs)
	if #fargs == 0 then
		vim.notify("bzl.nvim usage: Bzl targets [testable|runnable] [here] | Bzl sync", vim.log.levels.INFO)
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

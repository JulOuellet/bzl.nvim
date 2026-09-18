local M = {}

---Optional. The plugin works with defaults if this is never called.
---@param opts table|nil
function M.setup(opts)
	require("bzl.config").setup(opts)
end

function M.targets(...)
	require("bzl.picker").targets(...)
end

---Refresh targets and synchronize the workspace's supported languages.
function M.sync(arg)
	local root = vim.b.bzl_workspace_root or require("bzl.cli").workspace_root()
	if arg == "log" then
		require("bzl.sync_log").open(root)
		return
	elseif arg then
		vim.notify("bzl.nvim usage: Bzl sync [log]", vim.log.levels.ERROR)
		return
	end
	vim.notify("bzl.nvim: syncing targets...", vim.log.levels.INFO)
	local start = vim.uv.hrtime()
	require("bzl.sync").run(root, function(result)
		if not result then
			return -- sync reports failures and retains the old model
		end
		local ms = math.floor((vim.uv.hrtime() - start) / 1e6)
		local msg = ("bzl.nvim: synced %d targets in %d ms"):format(result.targets, ms)
		local level = vim.log.levels.INFO
		local names = vim.tbl_keys(result.languages)
		table.sort(names)
		for _, name in ipairs(names) do
			local entry = result.languages[name]
			if entry.model then
				msg = msg .. (", %s: %s -> %d clients"):format(name, entry.model.summary, entry.clients)
			else
				msg, level = msg .. (", %s: failed (previous configuration kept)"):format(name), vim.log.levels.WARN
			end
		end
		vim.notify(msg, level)
	end)
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
		vim.notify("bzl.nvim usage: Bzl targets [testable|runnable] [here] | Bzl sync [log]", vim.log.levels.INFO)
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

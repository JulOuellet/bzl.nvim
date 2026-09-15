local M = {}

---Optional. The plugin works with defaults if this is never called.
---@param opts table|nil
function M.setup(opts)
	require("bzl.config").setup(opts)
end

function M.targets(...)
	require("bzl.picker").targets(...)
end

---Refresh scoped targets and language-specific build metadata.
function M.sync(...)
	local args, root = { ... }, require("bzl.cli").workspace_root()
	if args[1] == "here" and #args == 1 and root then
		local scope = require("bzl.targets").project_of(vim.api.nvim_buf_get_name(0), root)
		if not scope then
			vim.notify("bzl.nvim: this file is not inside a bazel package", vim.log.levels.WARN)
			return
		end
		args = { scope == "" and "//..." or "//" .. scope .. "/..." }
	else
		for _, arg in ipairs(args) do
			if not arg:match("^//") and not arg:match("^@") then
				vim.notify("bzl.nvim: sync expects 'here' or Bazel target patterns", vim.log.levels.ERROR)
				return
			end
		end
	end
	return require("bzl.sync").start({ root = root, targets = args })
end

function M.cancel()
	local stopped = require("bzl.sync").cancel()
	vim.notify(stopped and "bzl.nvim: sync cancelled" or "bzl.nvim: no active sync", vim.log.levels.INFO)
end

function M.status()
	local state = require("bzl.sync").status()
	if not state then
		vim.notify("bzl.nvim: no sync result for this workspace", vim.log.levels.INFO)
		return
	end
	local lines =
		{ "bzl.nvim: " .. state.root, "Scope: " .. table.concat(state.scope, " "), "Targets: " .. state.targets }
	for name, result in pairs(state.adapters) do
		lines[#lines + 1] = name .. ": " .. result.status .. (result.message and " — " .. result.message or "")
		local applied = (state.applied or {})[name]
		if applied then
			lines[#lines + 1] = ("  Applied to %d clients"):format(applied.clients)
			vim.list_extend(lines, applied.notes)
		end
	end
	vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end

M.subcommands = {
	targets = M.targets,
	sync = M.sync,
	cancel = M.cancel,
	status = M.status,
}

---Entry point for the :Bzl user command. Arguments after the
---subcommand name are forwarded to it.
---@param fargs string[]
function M.cmd(fargs)
	if #fargs == 0 then
		vim.notify(
			"bzl.nvim usage: Bzl targets [testable|runnable] [here] | Bzl sync [here|targets...] | Bzl cancel | Bzl status",
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

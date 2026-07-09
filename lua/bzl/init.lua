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

M.subcommands = {
	hello = M.hello,
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

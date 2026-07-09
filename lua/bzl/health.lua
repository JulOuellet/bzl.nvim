local M = {}

function M.check()
	vim.health.start("bzl.nvim")

	if vim.fn.has("nvim-0.10") == 1 then
		vim.health.ok("Neovim >= 0.10")
	else
		vim.health.error("bzl.nvim requires Neovim >= 0.10")
	end

	local bazel_cmd = require("bzl.config").get().bazel_cmd
	if vim.fn.executable(bazel_cmd) == 1 then
		vim.health.ok(("`%s` is executable"):format(bazel_cmd))
	else
		vim.health.warn(("`%s` not found in PATH"):format(bazel_cmd), {
			"Install bazel/bazelisk, or point `bazel_cmd` at your binary in setup()",
		})
	end
end

return M

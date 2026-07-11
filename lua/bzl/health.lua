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

	if pcall(require, "snacks") then
		vim.health.ok("snacks.nvim is installed")
	else
		vim.health.warn("snacks.nvim not found", {
			"The target picker (:Bzl targets) requires folke/snacks.nvim",
		})
	end
end

return M

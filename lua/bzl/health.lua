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

	vim.health.start("Python sync")
	local root = require("bzl.cli").workspace_root()
	local model = root and require("bzl.python").get(root)
	if model then
		vim.health.ok(("%d configured Python targets, %d import paths"):format(model.targets, #model.paths))
		if model.interpreter then
			vim.health.info("Bazel Python interpreter: " .. model.interpreter)
		end
	else
		vim.health.info("No successful Python sync for this workspace yet; run :Bzl sync")
	end
end

return M

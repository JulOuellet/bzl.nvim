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

	local root = require("bzl.cli").workspace_root()
	for _, name in ipairs({ "python", "go" }) do
		vim.health.start(name .. " sync")
		if not require("bzl.config").get()[name].enabled then
			vim.health.info("Disabled")
		else
			local model = root and require("bzl.sync").get(root, name)
			if model then
				vim.health.ok(model.summary)
				if model.targets then
					vim.health.info(("%d configured targets"):format(model.targets))
				end
				if model.interpreter then
					vim.health.info("Bazel Python interpreter: " .. model.interpreter)
				end
				if model.driver then
					vim.health.info("Go package driver: " .. model.driver)
				end
			else
				vim.health.info("No successful sync for this workspace yet; run :Bzl sync")
			end
		end
	end
end

return M

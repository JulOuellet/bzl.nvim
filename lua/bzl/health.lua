local M = {}

function M.check()
	vim.health.start("bzl.nvim")

	if vim.fn.has("nvim-0.11") == 1 then
		vim.health.ok("Neovim >= 0.11")
	else
		vim.health.error("bzl.nvim requires Neovim >= 0.11")
	end

	local root = require("bzl.cli").workspace_root()
	local bazel_cmd = require("bzl.config").get(root).bazel_cmd
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
	if not root then
		vim.health.info("No Bazel workspace for the current buffer")
		return
	end
	vim.health.info("Workspace: " .. root)
	local state = require("bzl.sync").status(root)
	if not state then
		vim.health.info(
			"No sync result in this session. :Bzl sync extracts language metadata; Python aspect mode requires Bazel 8+ and rules_python."
		)
		return
	end
	for name, result in pairs(state.adapters) do
		local message = name .. ": " .. result.status .. " — " .. (result.message or "")
		if result.status == "ready" then
			vim.health.ok(message)
		else
			vim.health.warn(message)
		end
		local applied = (state.applied or {})[name]
		if applied then
			vim.health.info(("Applied to %d %s clients"):format(applied.clients, name))
			for _, note in ipairs(applied.notes) do
				vim.health.warn(note)
			end
		end
	end
end

return M

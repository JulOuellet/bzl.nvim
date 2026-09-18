if vim.g.loaded_bzl then
	return
end
vim.g.loaded_bzl = true

local group = vim.api.nvim_create_augroup("bzl", {})
vim.api.nvim_create_autocmd("BufWritePost", {
	group = group,
	pattern = {
		"BUILD",
		"BUILD.bazel",
		"*.bzl",
		"MODULE.bazel",
		"MODULE.bazel.lock",
		"WORKSPACE",
		"WORKSPACE.bazel",
		".bazelrc",
	},
	desc = "Drop the bzl.nvim target cache when build files change",
	callback = function(event)
		-- an unloaded plugin has no cache to drop; don't load it just for this
		if not package.loaded["bzl.targets"] and not package.loaded["bzl.sync"] then
			return
		end
		local root = require("bzl.cli").workspace_root(event.buf)
		if package.loaded["bzl.targets"] then
			require("bzl.targets").refresh(root)
		end
		if package.loaded["bzl.sync"] then
			require("bzl.sync").invalidate(root)
		end
	end,
})

vim.api.nvim_create_autocmd("LspAttach", {
	group = group,
	desc = "Apply the last successful sync to newly attached clients",
	callback = function(event)
		if package.loaded["bzl.sync"] then
			local client = vim.lsp.get_client_by_id(event.data.client_id)
			if client then
				require("bzl.sync").attach(client)
			end
		end
	end,
})

vim.api.nvim_create_user_command("Bzl", function(cmd)
	require("bzl").cmd(cmd.fargs)
end, {
	nargs = "*",
	desc = "bzl.nvim",
	complete = function(_, line)
		local function matching(candidates, prefix, used)
			table.sort(candidates)
			return vim.tbl_filter(function(name)
				return not (used and used[name]) and name:find(prefix, 1, true) == 1
			end, candidates)
		end

		-- later positions: picker arguments, minus the ones already typed
		local sub, rest = line:match("^%s*Bzl%s+(%S+)%s+(.*)$")
		if sub then
			local args_for = {
				targets = { "here", "runnable", "testable" },
				sync = { "log" },
			}
			if not args_for[sub] then
				return {}
			end
			local used = {}
			for word in rest:gmatch("(%S+)%s") do
				used[word] = true
			end
			return matching(args_for[sub], rest:match("(%S*)$"), used)
		end

		local prefix = line:match("^%s*Bzl%s+(%S*)$")
		if not prefix then
			return {}
		end
		return matching(vim.tbl_keys(require("bzl").subcommands), prefix)
	end,
})

if vim.g.loaded_bzl then
	return
end
vim.g.loaded_bzl = true

vim.api.nvim_create_autocmd("BufWritePost", {
	group = vim.api.nvim_create_augroup("bzl", {}),
	pattern = { "BUILD", "BUILD.bazel", "*.bzl", "MODULE.bazel", "WORKSPACE", "WORKSPACE.bazel" },
	desc = "Drop the bzl.nvim target cache when build files change",
	callback = function()
		-- an unloaded plugin has no cache to drop; don't load it just for this
		if package.loaded["bzl.targets"] then
			require("bzl.targets").refresh()
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
				tree = { "here", "runnable", "testable" },
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

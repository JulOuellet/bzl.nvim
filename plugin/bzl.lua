if vim.g.loaded_bzl then
	return
end
vim.g.loaded_bzl = true

vim.api.nvim_create_user_command("Bzl", function(cmd)
	require("bzl").cmd(cmd.fargs)
end, {
	nargs = "*",
	desc = "bzl.nvim",
	complete = function(_, line)
		local prefix = line:match("^%s*Bzl%s+(%S*)$")
		if not prefix then
			return {}
		end
		local names = vim.tbl_keys(require("bzl").subcommands)
		table.sort(names)
		return vim.tbl_filter(function(name)
			return name:find(prefix, 1, true) == 1
		end, names)
	end,
})

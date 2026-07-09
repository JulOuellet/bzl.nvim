-- Minimal init for tests. Used both by the outer test runner (`make test`)
-- and by the child neovim instances spawned inside tests.
-- Must be run from the plugin root.
vim.cmd([[let &rtp.=','.getcwd()]])

-- --noplugin skips automatic plugin/ sourcing, so do it explicitly
vim.cmd("runtime! plugin/bzl.lua")

if #vim.api.nvim_list_uis() == 0 then
	vim.cmd("set rtp+=deps/mini.nvim")
	require("mini.test").setup()
end

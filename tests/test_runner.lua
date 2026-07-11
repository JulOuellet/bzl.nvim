local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
			child.lua([[
				_G.notifications = {}
				vim.notify = function(msg, level)
					table.insert(_G.notifications, { msg = msg, level = level })
				end
			]])
		end,
		post_once = child.stop,
	},
})

T["execute"] = MiniTest.new_set()

T["execute"]["reports missing workspace"] = function()
	-- child cwd is the plugin root, which is not a bazel workspace
	child.lua([[require("bzl.runner").execute("run", "//:hello")]])
	local notifications = child.lua_get([[_G.notifications]])
	MiniTest.expect.equality(#notifications, 1)
	MiniTest.expect.equality(notifications[1].msg:find("no bazel workspace", 1, true) ~= nil, true)
end

T["execute"]["opens a terminal split for a real run"] = function()
	if vim.fn.executable(require("bzl.config").get().bazel_cmd) == 0 then
		MiniTest.skip("bazel not available")
	end
	child.cmd("edit tests/fixture/BUILD.bazel")
	child.lua([[require("bzl.runner").execute("run", "//:hello")]])
	local term_bufs = child.lua_get([[#vim.tbl_filter(function(b)
		return vim.bo[b].buftype == "terminal"
	end, vim.api.nvim_list_bufs())]])
	MiniTest.expect.equality(term_bufs, 1)
	MiniTest.expect.equality(child.lua_get([[#vim.api.nvim_tabpage_list_wins(0)]]), 2)
end

T["rerun"] = MiniTest.new_set()

T["rerun"]["notifies when there is no previous run"] = function()
	child.lua([[require("bzl.runner").rerun()]])
	local notifications = child.lua_get([[_G.notifications]])
	MiniTest.expect.equality(#notifications, 1)
	MiniTest.expect.equality(notifications[1].msg, "bzl.nvim: nothing to re-run yet")
	MiniTest.expect.equality(notifications[1].level, vim.log.levels.WARN)
end

return T

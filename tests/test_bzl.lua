local child = MiniTest.new_child_neovim()

local T = MiniTest.new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
		end,
		post_once = child.stop,
	},
})

T["config"] = MiniTest.new_set()

T["config"]["applies defaults without setup()"] = function()
	MiniTest.expect.equality(child.lua_get([[require("bzl.config").get().bazel_cmd]]), "bazel")
end

T["config"]["setup() overrides defaults"] = function()
	child.lua([[require("bzl").setup({ bazel_cmd = "bazelisk" })]])
	MiniTest.expect.equality(child.lua_get([[require("bzl.config").get().bazel_cmd]]), "bazelisk")
end

T[":Bzl"] = MiniTest.new_set()

T[":Bzl"]["is registered"] = function()
	MiniTest.expect.equality(child.lua_get([[vim.fn.exists(":Bzl")]]), 2)
end

T[":Bzl"]["completes subcommands"] = function()
	MiniTest.expect.equality(
		child.lua_get([[vim.fn.getcompletion("Bzl ", "cmdline")]]),
		{ "hello", "rerun", "sync", "targets" }
	)
end

T[":Bzl"]["sync reports progress, then the failure"] = function()
	child.lua([[
		_G.notifications = {}
		vim.notify = function(msg)
			table.insert(_G.notifications, msg)
		end
	]])
	-- child cwd is the plugin root: not a bazel workspace, so sync must fail
	child.cmd("Bzl sync")
	child.lua([[vim.wait(5000, function() return #_G.notifications >= 2 end, 50)]])
	local notifications = child.lua_get([[_G.notifications]])
	MiniTest.expect.equality(notifications[1], "bzl.nvim: syncing targets...")
	MiniTest.expect.equality(notifications[2]:find("no bazel workspace", 1, true) ~= nil, true)
end

T[":Bzl"]["sync re-queries through real bazel"] = function()
	if vim.fn.executable(require("bzl.config").get().bazel_cmd) == 0 then
		MiniTest.skip("bazel not available")
	end
	child.lua([[
		_G.notifications = {}
		vim.notify = function(msg)
			table.insert(_G.notifications, msg)
		end
	]])
	child.cmd("edit tests/fixture/BUILD.bazel")
	child.cmd("Bzl sync")
	child.lua([[vim.wait(120000, function() return #_G.notifications >= 2 end, 100)]])
	local notifications = child.lua_get([[_G.notifications]])
	MiniTest.expect.equality(notifications[2]:find("synced 5 targets", 1, true) ~= nil, true)
	-- the python step ran too: the fixture has no pip deps, so 0 paths
	MiniTest.expect.equality(notifications[2]:find("0 python paths", 1, true) ~= nil, true)
end

T[":Bzl"]["registers the build-file autocmds"] = function()
	-- one autocmd entry is created per pattern
	local patterns = child.lua_get([[vim.tbl_map(function(au)
		return au.pattern
	end, vim.api.nvim_get_autocmds({ group = "bzl", event = "BufWritePost" }))]])
	table.sort(patterns)
	MiniTest.expect.equality(patterns, {
		"*.bzl",
		"BUILD",
		"BUILD.bazel",
		"MODULE.bazel",
		"WORKSPACE",
		"WORKSPACE.bazel",
	})
end

T[":Bzl"]["reports unknown subcommand"] = function()
	MiniTest.expect.error(function()
		child.cmd("Bzl not_a_real_subcommand")
	end, 'unknown subcommand "not_a_real_subcommand"')
end

return T

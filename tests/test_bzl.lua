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
	MiniTest.expect.equality(child.lua_get([[require("bzl.config").get().picker.preview]]), false)
end

T["config"]["setup() overrides defaults"] = function()
	child.lua([[require("bzl").setup({ bazel_cmd = "bazelisk" })]])
	MiniTest.expect.equality(child.lua_get([[require("bzl.config").get().bazel_cmd]]), "bazelisk")
end

T["config"]["normalizes language switches and rejects malformed options before replacing config"] = function()
	child.lua([[require("bzl").setup({ go = false, python = true })]])
	MiniTest.expect.equality(child.lua_get([[require("bzl.config").get().go.enabled]]), false)
	MiniTest.expect.equality(child.lua_get([[require("bzl.config").get().python.targets]]), {})
	MiniTest.expect.error(function()
		child.lua([[require("bzl").setup({ go = "no" })]])
	end, "go must be a table or boolean")
	MiniTest.expect.equality(child.lua_get([[require("bzl.config").get().go.enabled]]), false)
	-- Health must also accept shorthand switches.
	child.cmd("checkhealth bzl")
	MiniTest.expect.equality(
		child.lua_get(
			[[table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"):find("Disabled", 1, true) ~= nil]]
		),
		true
	)
end

T[":Bzl"] = MiniTest.new_set()

T[":Bzl"]["is registered"] = function()
	MiniTest.expect.equality(child.lua_get([[vim.fn.exists(":Bzl")]]), 2)
end

T[":Bzl"]["completes subcommands"] = function()
	MiniTest.expect.equality(child.lua_get([[vim.fn.getcompletion("Bzl ", "cmdline")]]), { "sync", "targets" })
end

T[":Bzl"]["completes picker arguments, minus the ones already used"] = function()
	MiniTest.expect.equality(
		child.lua_get([[vim.fn.getcompletion("Bzl targets ", "cmdline")]]),
		{ "here", "runnable", "testable" }
	)
	MiniTest.expect.equality(
		child.lua_get([[vim.fn.getcompletion("Bzl targets testable ", "cmdline")]]),
		{ "here", "runnable" }
	)
	MiniTest.expect.equality(child.lua_get([[vim.fn.getcompletion("Bzl sync ", "cmdline")]]), { "log" })
	MiniTest.expect.equality(child.lua_get([[vim.fn.getcompletion("Bzl sync log ", "cmdline")]]), {})
end

T[":Bzl"]["rejects an unknown picker argument"] = function()
	child.lua([[
		_G.notifications = {}
		vim.notify = function(msg)
			table.insert(_G.notifications, msg)
		end
	]])
	child.cmd("Bzl targets bogus")
	local notifications = child.lua_get([[_G.notifications]])
	MiniTest.expect.equality(#notifications, 1)
	MiniTest.expect.equality(notifications[1]:find('unknown argument "bogus"', 1, true) ~= nil, true)
end

T[":Bzl"]["prints usage without a subcommand"] = function()
	child.lua([[
		_G.notifications = {}
		vim.notify = function(msg)
			table.insert(_G.notifications, msg)
		end
	]])
	child.cmd("Bzl")
	local notifications = child.lua_get([[_G.notifications]])
	MiniTest.expect.equality(#notifications, 1)
	MiniTest.expect.equality(notifications[1]:find("usage", 1, true) ~= nil, true)
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
	-- Non-Python workspaces need no configured analysis or Python build.
	MiniTest.expect.equality(notifications[2]:find("python", 1, true), nil)
end

T[":Bzl"]["sync keeps its workspace when the current buffer changes"] = function()
	child.cmd("edit tests/fixture/BUILD.bazel")
	child.lua([[
		require("bzl.targets").list = function(root, on_done)
			_G.sync_root = root
			vim.cmd("enew")
			on_done({ { kind = "py_library", label = "//:app" } })
		end
		require("bzl.languages.python").prepare = function(ctx, done)
			_G.adapter_root = ctx.root
			done({ paths = {}, targets = 1, summary = "0 python paths" })
		end
		require("bzl").sync()
	]])
	MiniTest.expect.equality(child.lua_get([[_G.sync_root:match("tests/fixture$")]]), "tests/fixture")
	MiniTest.expect.equality(child.lua_get([[_G.adapter_root]]), child.lua_get([[_G.sync_root]]))
	MiniTest.expect.equality(child.lua_get([[require("bzl.sync").get(_G.sync_root, "python").targets]]), 1)
end

T[":Bzl"]["registers the build-file autocmds"] = function()
	-- one autocmd entry is created per pattern
	local patterns = child.lua_get([[vim.tbl_map(function(au)
		return au.pattern
	end, vim.api.nvim_get_autocmds({ group = "bzl", event = "BufWritePost" }))]])
	table.sort(patterns)
	MiniTest.expect.equality(patterns, {
		"*.bzl",
		".bazelrc",
		"BUILD",
		"BUILD.bazel",
		"MODULE.bazel",
		"MODULE.bazel.lock",
		"WORKSPACE",
		"WORKSPACE.bazel",
	})
end

T[":Bzl"]["build-file writes keep unused modules unloaded"] = function()
	child.cmd("edit tests/go_fixture/deps/BUILD.bazel")
	child.lua([[vim.api.nvim_exec_autocmds("BufWritePost", { buffer = 0 })]])
	MiniTest.expect.equality(child.lua_get([[package.loaded["bzl.cli"] ~= nil]]), false)
	MiniTest.expect.equality(child.lua_get([[package.loaded["bzl.targets"] ~= nil]]), false)
	MiniTest.expect.equality(child.lua_get([[package.loaded["bzl.sync"] ~= nil]]), false)
end

T[":Bzl"]["reports unknown subcommand"] = function()
	MiniTest.expect.error(function()
		child.cmd("Bzl not_a_real_subcommand")
	end, 'unknown subcommand "not_a_real_subcommand"')
end

return T

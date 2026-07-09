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
	MiniTest.expect.equality(child.lua_get([[vim.fn.getcompletion("Bzl ", "cmdline")]]), { "hello" })
end

T[":Bzl"]["reports unknown subcommand"] = function()
	MiniTest.expect.error(function()
		child.cmd("Bzl not_a_real_subcommand")
	end, 'unknown subcommand "not_a_real_subcommand"')
end

return T

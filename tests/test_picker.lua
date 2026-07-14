local T = MiniTest.new_set()

T["make_items"] = MiniTest.new_set()

local make_items = require("bzl.picker").make_items

T["make_items"]["maps targets to picker items"] = function()
	local targets = {
		{ kind = "sh_binary", label = "//:hello" },
		{ kind = "sh_test", label = "//:hello_test" },
		{ kind = "sh_library", label = "//lib:greetings" },
	}
	MiniTest.expect.equality(make_items(targets), {
		{ text = "//:hello sh_binary", label = "//:hello", kind = "sh_binary" },
		{ text = "//:hello_test sh_test", label = "//:hello_test", kind = "sh_test" },
		{ text = "//lib:greetings sh_library", label = "//lib:greetings", kind = "sh_library" },
	})
end

T["make_items"]["keeps target order"] = function()
	local targets = {
		{ kind = "sh_test", label = "//b:b" },
		{ kind = "sh_test", label = "//a:a" },
	}
	local labels = vim.tbl_map(function(item)
		return item.label
	end, make_items(targets))
	MiniTest.expect.equality(labels, { "//b:b", "//a:a" })
end

T["make_items"]["returns an empty list for no targets"] = function()
	MiniTest.expect.equality(make_items({}), {})
end

T["filter_targets"] = MiniTest.new_set()

local filter_targets = require("bzl.picker").filter_targets

local mixed = {
	{ kind = "sh_binary", label = "//:hello" },
	{ kind = "sh_test", label = "//:hello_test" },
	{ kind = "sh_library", label = "//lib:greetings" },
}

T["filter_targets"]["testable keeps only test kinds"] = function()
	MiniTest.expect.equality(filter_targets(mixed, "testable"), { { kind = "sh_test", label = "//:hello_test" } })
end

T["filter_targets"]["runnable keeps binaries but not tests"] = function()
	MiniTest.expect.equality(filter_targets(mixed, "runnable"), { { kind = "sh_binary", label = "//:hello" } })
end

T["filter_targets"]["nil filter returns the list unchanged"] = function()
	MiniTest.expect.equality(filter_targets(mixed, nil), mixed)
end

T["filter_targets"]["unknown filter returns nil"] = function()
	MiniTest.expect.equality(filter_targets(mixed, "bogus"), nil)
end

T["subtree_label"] = MiniTest.new_set()

T["subtree_label"]["builds wildcard labels"] = function()
	local subtree_label = require("bzl.picker").subtree_label
	MiniTest.expect.equality(subtree_label(""), "//...")
	MiniTest.expect.equality(subtree_label("services/api"), "//services/api/...")
end

T["in_project"] = MiniTest.new_set()

T["in_project"]["matches the directory and its subtree only"] = function()
	local in_project = require("bzl.picker").in_project
	MiniTest.expect.equality(in_project("//services:x", "services"), true)
	MiniTest.expect.equality(in_project("//services/api:x", "services"), true)
	MiniTest.expect.equality(in_project("//services2:x", "services"), false)
	MiniTest.expect.equality(in_project("//lib:x", "services"), false)
	MiniTest.expect.equality(in_project("//anything:x", ""), true)
end

T["verb_for"] = MiniTest.new_set()

local verb_for = require("bzl.picker").verb_for

T["verb_for"]["tests test targets"] = function()
	MiniTest.expect.equality(verb_for("sh_test"), "test")
	MiniTest.expect.equality(verb_for("java_test"), "test")
end

T["verb_for"]["runs binary targets"] = function()
	MiniTest.expect.equality(verb_for("sh_binary"), "run")
	MiniTest.expect.equality(verb_for("py_binary"), "run")
end

T["verb_for"]["builds everything else"] = function()
	MiniTest.expect.equality(verb_for("sh_library"), "build")
	MiniTest.expect.equality(verb_for("filegroup"), "build")
	-- suffix must be a suffix with the underscore, not a bare word
	MiniTest.expect.equality(verb_for("test"), "build")
end

local child = MiniTest.new_child_neovim()

T["targets"] = MiniTest.new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
		end,
		post_once = child.stop,
	},
})

-- the test child has no snacks.nvim on its runtimepath, which is exactly
-- the environment the pcall guard exists for
T["targets"]["degrades gracefully without snacks"] = function()
	child.lua([[
		_G.notifications = {}
		vim.notify = function(msg, level)
			table.insert(_G.notifications, { msg = msg, level = level })
		end
		require("bzl.picker").targets()
	]])
	local notifications = child.lua_get([[_G.notifications]])
	MiniTest.expect.equality(#notifications, 1)
	MiniTest.expect.equality(notifications[1].msg, "bzl.nvim: the target picker requires snacks.nvim")
	MiniTest.expect.equality(notifications[1].level, vim.log.levels.ERROR)
end

return T

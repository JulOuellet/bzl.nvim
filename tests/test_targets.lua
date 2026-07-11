local T = MiniTest.new_set()

T["parse"] = MiniTest.new_set()

local parse = require("bzl.targets").parse

T["parse"]["extracts kind and label"] = function()
	local output = table.concat({
		"sh_binary rule //:hello",
		"sh_test rule //:hello_test",
		"sh_library rule //lib:greetings",
	}, "\n")
	MiniTest.expect.equality(parse(output), {
		{ kind = "sh_binary", label = "//:hello" },
		{ kind = "sh_test", label = "//:hello_test" },
		{ kind = "sh_library", label = "//lib:greetings" },
	})
end

T["parse"]["skips lines that are not rule targets"] = function()
	local output = table.concat({
		"Loading: 3 packages loaded",
		"sh_test rule //:hello_test",
		"source file //:hello.sh",
	}, "\n")
	MiniTest.expect.equality(parse(output), { { kind = "sh_test", label = "//:hello_test" } })
end

T["parse"]["returns an empty list for empty output"] = function()
	MiniTest.expect.equality(parse(""), {})
end

T["parse_label"] = MiniTest.new_set()

local parse_label = require("bzl.targets").parse_label

T["parse_label"]["splits package and name"] = function()
	MiniTest.expect.equality(parse_label("//lib:greetings"), { package = "lib", name = "greetings" })
	MiniTest.expect.equality(parse_label("//foo/bar:baz"), { package = "foo/bar", name = "baz" })
end

T["parse_label"]["handles the root package"] = function()
	MiniTest.expect.equality(parse_label("//:hello"), { package = "", name = "hello" })
end

T["parse_label"]["rejects external and malformed labels"] = function()
	MiniTest.expect.equality(parse_label("@rules_shell//shell:sh_binary"), nil)
	MiniTest.expect.equality(parse_label("not a label"), nil)
	MiniTest.expect.equality(parse_label("//lib"), nil)
end

T["location"] = MiniTest.new_set()

local location = require("bzl.targets").location
local fixture_root = vim.fn.getcwd() .. "/tests/fixture"

T["location"]["finds the BUILD file and name line"] = function()
	MiniTest.expect.equality(
		location("//lib:greetings", fixture_root),
		{ file = fixture_root .. "/lib/BUILD.bazel", lnum = 4 }
	)
end

T["location"]["finds targets in the root package"] = function()
	MiniTest.expect.equality(location("//:hello", fixture_root), { file = fixture_root .. "/BUILD.bazel", lnum = 5 })
end

T["location"]["returns the file without a line for unknown names"] = function()
	MiniTest.expect.equality(location("//lib:nope", fixture_root), { file = fixture_root .. "/lib/BUILD.bazel" })
end

T["location"]["returns nil for a missing package"] = function()
	MiniTest.expect.equality(location("//nope:x", fixture_root), nil)
end

T["package_of"] = MiniTest.new_set()

local package_of = require("bzl.targets").package_of

T["package_of"]["resolves the root package"] = function()
	MiniTest.expect.equality(package_of(fixture_root .. "/hello.sh", fixture_root), "")
end

T["package_of"]["resolves a nested package"] = function()
	MiniTest.expect.equality(package_of(fixture_root .. "/lib/greet.sh", fixture_root), "lib")
end

T["package_of"]["returns nil outside the workspace"] = function()
	MiniTest.expect.equality(package_of(vim.fn.getcwd() .. "/README.md", fixture_root), nil)
end

T["integration"] = MiniTest.new_set()

T["integration"]["lists the fixture targets through real bazel"] = function()
	if vim.fn.executable(require("bzl.config").get().bazel_cmd) == 0 then
		MiniTest.skip("bazel not available")
	end

	local child = MiniTest.new_child_neovim()
	child.restart({ "-u", "scripts/minimal_init.lua" })
	child.cmd("edit tests/fixture/BUILD.bazel")
	child.lua([[
		_G.bzl_result = nil
		require("bzl.targets").list(function(targets)
			_G.bzl_result = targets or false
		end)
	]])
	-- generous timeout: the first run downloads deps and starts the bazel server
	child.lua([[vim.wait(120000, function() return _G.bzl_result ~= nil end, 100)]])
	local result = child.lua_get([[_G.bzl_result]])
	MiniTest.expect.no_equality(result, false)
	local labels = vim.tbl_map(function(t)
		return t.label
	end, result)
	table.sort(labels)
	MiniTest.expect.equality(labels, {
		"//:failing_test",
		"//:hello",
		"//:hello_test",
		"//:scripts",
		"//lib:greetings",
	})
	child.stop()
end

T["integration"]["lists a single package through real bazel"] = function()
	if vim.fn.executable(require("bzl.config").get().bazel_cmd) == 0 then
		MiniTest.skip("bazel not available")
	end

	local child = MiniTest.new_child_neovim()
	child.restart({ "-u", "scripts/minimal_init.lua" })
	child.cmd("edit tests/fixture/lib/greet.sh")
	child.lua([[
		_G.bzl_result = nil
		require("bzl.targets").list_package("lib", function(targets)
			_G.bzl_result = targets or false
		end)
	]])
	child.lua([[vim.wait(120000, function() return _G.bzl_result ~= nil end, 100)]])
	local result = child.lua_get([[_G.bzl_result]])
	MiniTest.expect.equality(result, { { kind = "sh_library", label = "//lib:greetings" } })
	child.stop()
end

return T

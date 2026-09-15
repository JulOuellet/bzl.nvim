local eq = MiniTest.expect.equality
local tmp
local T = MiniTest.new_set({
	hooks = {
		pre_case = function()
			tmp = vim.fn.tempname()
			vim.fn.mkdir(tmp, "p")
		end,
		post_case = function()
			vim.fn.delete(tmp, "rf")
		end,
	},
})

T["clangd rejects shell commands and accepts argv databases"] = function()
	local adapter = require("bzl.languages.cpp")
	local ctx = {
		root = tmp,
		config = { sync = { languages = { cpp = { database = "compile_commands.json", refresh = {} } } } },
	}
	local function discover(entry)
		vim.fn.writefile({ vim.json.encode({ entry }) }, tmp .. "/compile_commands.json")
		local result
		adapter.discover(ctx, function(value)
			result = value
		end)
		return result
	end
	eq(discover({ directory = tmp, file = "main.cc", command = "cc main.cc" }).status, "unsupported")
	local result = discover({ directory = tmp, file = "main.cc", arguments = { "cc", "-Ispace here", "main.cc" } })
	eq(result.status, "ready")
	eq(result.metadata.commands[tmp .. "/main.cc"].compilationCommand, { "cc", "-Ispace here", "main.cc" })
end

T["clangd preserves user commands and reports removed scope"] = function()
	local adapter = require("bzl.languages.cpp")
	local original = { workingDirectory = tmp, compilationCommand = { "clang", "user.cc" } }
	local client = {
		settings = { compilationDatabaseChanges = { user = original } },
		notify = function()
			return true
		end,
	}
	eq(adapter.apply({}, { commands = { user = { compilationCommand = { "other" } } } }, client), false)
	eq(client.settings.compilationDatabaseChanges.user, original)
	eq(adapter.apply({}, { commands = { plugin = original } }, client), true)
	local applied, reason = adapter.apply({}, { commands = {} }, client)
	eq(applied, false)
	eq(reason:find("restart clangd", 1, true) ~= nil, true)
end

T["Rust validates crate source existence before applying"] = function()
	local ctx =
		{ root = tmp, config = { sync = { languages = { rust = { project = "rust-project.json", refresh = {} } } } } }
	vim.fn.writefile({ vim.json.encode({ crates = { { root_module = "lib.rs" } } }) }, tmp .. "/rust-project.json")
	local result
	local adapter = require("bzl.languages.rust")
	adapter.discover(ctx, function(value)
		result = value
	end)
	eq(result.status, "partial")
	vim.fn.writefile({}, tmp .. "/lib.rs")
	adapter.discover(ctx, function(value)
		result = value
	end)
	eq(result.status, "ready")
	local client = {
		settings = { ["rust-analyzer"] = { linkedProjects = { "/user/project.json" } } },
		notify = function()
			return true
		end,
	}
	adapter.apply(ctx, result.metadata, client)
	eq(client.settings["rust-analyzer"].linkedProjects, { "/user/project.json", tmp .. "/rust-project.json" })
end

T["Go keeps explicit user package drivers"] = function()
	local client = {
		settings = { gopls = { env = { GOPACKAGESDRIVER = "/user/driver", KEEP = "yes" } } },
		notify = function()
			return true
		end,
	}
	eq(require("bzl.languages.go").apply({}, { driver = "/plugin/driver" }, client), false)
	eq(client.settings.gopls.env, { GOPACKAGESDRIVER = "/user/driver", KEEP = "yes" })
end

T["Python project configuration conflicts are reported without overwriting settings"] = function()
	vim.fn.writefile({ '{ "extraPaths": ["user"] }' }, tmp .. "/pyrightconfig.json")
	local client = {
		name = "pyright",
		settings = { untouched = true },
		notify = function()
			error("must not notify")
		end,
	}
	eq(require("bzl.languages.python").apply({ root = tmp }, { paths = { tmp } }, client), false)
	eq(client.settings, { untouched = true })
end

return T

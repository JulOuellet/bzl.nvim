local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local function client(name, root)
	return {
		name = name,
		root_dir = root,
		settings = {},
		notifications = {},
		notify = function(self, method, params)
			table.insert(self.notifications, { method = method, params = params })
		end,
	}
end

local cli, sync, original_sync, original_run, original_clients, original_notify, tmp, c, notifications
T["sync"] = MiniTest.new_set({
	hooks = {
		pre_case = function()
			original_sync = package.loaded["bzl.sync"]
			package.loaded["bzl.sync"] = nil
			sync = require("bzl.sync")
			cli = require("bzl.cli")
			original_run, original_clients, original_notify = cli.run, vim.lsp.get_clients, vim.notify
			tmp = vim.fn.tempname()
			vim.fn.mkdir(tmp .. "/_main", "p")
			c, notifications = client("basedpyright", tmp), {}
			vim.lsp.get_clients = function()
				return { c }
			end
			vim.notify = function(message)
				table.insert(notifications, message)
			end
			require("bzl.config").setup({ python = { targets = { "//:app" } } })
			cli.run = function(_, args, done)
				if args[1] == "query" then
					done({ code = 0, stdout = "py_binary rule //:app\nsh_test rule //:test\n" })
				elseif args[1] == "cquery" then
					done({
						code = 0,
						stdout = vim.json.encode({ label = "//:app", imports = {}, roots = {}, generated = {} }),
					})
				else
					done({ code = 0, stdout = tmp .. "/_main\n" })
				end
				return true
			end
		end,
		post_case = function()
			package.loaded["bzl.sync"] = original_sync
			cli.run, vim.lsp.get_clients, vim.notify = original_run, original_clients, original_notify
			require("bzl.config").setup()
			vim.fn.delete(tmp, "rf")
		end,
	},
})

T["sync"]["builds before publishing and replays to clients that start later"] = function()
	local commands, run = {}, cli.run
	cli.run = function(root, args, done)
		table.insert(commands, args[1])
		eq(sync.get(tmp, "python"), nil)
		return run(root, args, done)
	end
	local result
	sync.run(tmp, function(value)
		result = value
	end)
	eq(commands, { "query", "cquery", "build", "info" })
	eq(result.targets, 2)
	eq(result.languages.python.clients, 1)
	eq(result.languages.python.model.paths, { tmp })
	local later = client("pyright", tmp)
	sync.attach(later)
	eq(later.settings.python.analysis.extraPaths, { tmp })
end

T["sync"]["selects discovered Python rules unless targets are configured"] = function()
	local run = cli.run
	for _, labels in ipairs({ {}, { "//:selected" } }) do
		require("bzl.config").setup({ python = { targets = labels } })
		cli.run = function(root, args, done)
			if args[1] == "cquery" then
				eq(args[2], "config(set(" .. (labels[1] or "//:app") .. "), target)")
			end
			return run(root, args, done)
		end
		local calls = 0
		sync.run(tmp, function(result)
			eq(result.targets, 2)
			calls = calls + 1
		end)
		eq(calls, 1)
	end
end

T["sync"]["retains the last model and client settings on any stage failure"] = function()
	sync.run(tmp, function() end)
	local before = vim.deepcopy(c.settings)
	local successful = cli.run
	for _, stage in ipairs({ "query", "cquery", "build", "info" }) do
		cli.run = function(root, args, done)
			if args[1] == stage then
				done({ code = 1, stderr = "simulated failure" })
				return true
			end
			return successful(root, args, done)
		end
		local calls = 0
		sync.run(tmp, function(value)
			eq(value and value.languages.python.model, nil)
			calls = calls + 1
		end)
		eq(calls, 1)
		eq(c.settings, before)
		eq(sync.get(tmp, "python").paths, { tmp })
	end
end

T["sync"]["completes exactly once when a command cannot start"] = function()
	cli.run = function()
		return false
	end
	local calls = 0
	sync.run(tmp, function(value)
		eq(value and value.languages.python.model, nil)
		calls = calls + 1
	end)
	eq(calls, 1)
	eq(sync.get(tmp, "python"), nil)
end

T["sync"]["rejects overlapping syncs and discards results invalidated by an edit"] = function()
	local run = cli.run
	for _, stage in ipairs({ "query", "cquery" }) do
		local pending
		cli.run = function(root, args, done)
			if args[1] == stage then
				pending = function()
					run(root, args, done)
				end
				return true
			end
			return run(root, args, done)
		end
		local first, second = 0, 0
		sync.run(tmp, function(value)
			eq(value and value.languages.python.model, nil)
			first = first + 1
		end)
		sync.run(tmp, function(value)
			eq(value and value.languages.python.model, nil)
			second = second + 1
		end)
		eq(second, 1)
		sync.invalidate(tmp)
		pending()
		eq(first, 1)
		eq(sync.get(tmp, "python"), nil)
		eq(#c.notifications, 0)
	end
end

T["sync"]["clears managed paths when there are no Python targets"] = function()
	sync.run(tmp, function() end)
	require("bzl.config").setup()
	cli.run = function(_, args, done)
		eq(args[1], "query")
		done({ code = 0, stdout = "sh_test rule //:test\n" })
		return true
	end
	sync.run(tmp, function(result)
		eq(#result.languages.python.model.paths, 0)
		eq(result.targets, 1)
	end)
	eq(c.settings.basedpyright.analysis.extraPaths, {})
end

T["sync"]["keeps one configuration throughout the commands and discards changed settings"] = function()
	local execute = cli.run
	local commands = 0
	cli.run = function(root, args, done, config)
		commands = commands + 1
		if args[1] ~= "query" then
			eq(config.build_flags, {})
		end
		if args[1] == "query" then
			require("bzl.config").setup({ python = { targets = { "//:app" } }, build_flags = { "--config=other" } })
		end
		return execute(root, args, done)
	end
	sync.run(tmp, function(value)
		eq(value and value.languages.python.model, nil)
	end)
	eq(commands, 1)
	eq(sync.get(tmp, "python"), nil)
	eq(#c.notifications, 0)
end

T["sync"]["a failed language retains its model while the other language updates"] = function()
	local py, go = require("bzl.languages.python"), require("bzl.languages.go")
	local py_prepare, go_prepare, run = py.prepare, go.prepare, cli.run
	local gopls = client("gopls", tmp)
	vim.lsp.get_clients = function()
		return { c, gopls }
	end
	cli.run = function(root, args, done, config)
		if args[1] == "query" then
			done({ code = 0, stdout = "py_binary rule //:app\ngo_library rule //:go\n" })
			return true
		end
		return run(root, args, done, config)
	end
	local ok, err = pcall(function()
		go.prepare = function(_, done)
			done({ driver = "/first", summary = "ready" })
		end
		sync.run(tmp, function() end)
		local before = vim.deepcopy(c.settings)
		py.prepare = function(_, done)
			done(nil, "Python failed")
		end
		go.prepare = function(_, done)
			done({ driver = "/second", summary = "ready" })
		end
		sync.run(tmp, function(result)
			eq(result.languages.python.error, "Python failed")
			eq(result.languages.go.clients, 1)
		end)
		eq(c.settings, before)
		eq(sync.get(tmp, "python").paths, { tmp })
		eq(gopls.settings.gopls.env.GOPACKAGESDRIVER, "/second")
		py.prepare = py_prepare
		go.prepare = function(_, done)
			done(nil, "Go failed")
		end
		sync.run(tmp, function(result)
			eq(result.languages.python.clients, 1)
			eq(result.languages.go.error, "Go failed")
		end)
		eq(sync.get(tmp, "go").driver, "/second")
		eq(gopls.settings.gopls.env.GOPACKAGESDRIVER, "/second")
	end)
	py.prepare, go.prepare = py_prepare, go_prepare
	assert(ok, err)
end

T["sync"]["disabled adapters neither build nor reapply saved settings"] = function()
	sync.run(tmp, function() end)
	require("bzl.config").setup({ python = { enabled = false }, go = { enabled = false } })
	cli.run = function(_, args, done)
		eq(args[1], "query")
		done({ code = 0, stdout = "py_binary rule //:app\ngo_library rule //:go\n" })
		return true
	end
	sync.run(tmp, function(result)
		eq(result.languages, {})
	end)
	local later = client("pyright", tmp)
	sync.attach(later)
	eq(#later.notifications, 0)
end

T["sync"]["an edit during Go preparation discards both staged models"] = function()
	local go = require("bzl.languages.go")
	local prepare, run = go.prepare, cli.run
	local pending
	go.prepare = function(_, done)
		pending = done
	end
	cli.run = function(root, args, done, config)
		if args[1] == "query" then
			done({ code = 0, stdout = "py_binary rule //:app\ngo_library rule //:go\n" })
			return true
		end
		return run(root, args, done, config)
	end
	local ok, err = pcall(function()
		local calls = 0
		sync.run(tmp, function(result)
			eq(result, nil)
			calls = calls + 1
		end)
		eq(sync.get(tmp, "python"), nil)
		sync.invalidate(tmp)
		pending({ driver = "/ready", summary = "ready" })
		eq(calls, 1)
		eq(sync.get(tmp, "python"), nil)
		eq(sync.get(tmp, "go"), nil)
		eq(#c.notifications, 0)
	end)
	go.prepare = prepare
	assert(ok, err)
end

return T

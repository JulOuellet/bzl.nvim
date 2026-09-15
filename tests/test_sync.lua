local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local cli = require("bzl.cli")
local config = require("bzl.config")
local util = require("bzl.languages.util")
local python = require("bzl.languages.python")

local function await(predicate)
	eq(vim.wait(5000, predicate, 10), true)
end

T["process"] = MiniTest.new_set({ hooks = {
	post_case = function()
		config.setup()
	end,
} })

T["process"]["callback on spawn failure is scheduled exactly once"] = function()
	config.setup({ bazel_cmd = "bzl-executable-does-not-exist" })
	local results = {}
	local handle = cli.run(vim.fn.getcwd(), { "query" }, function(result)
		results[#results + 1] = result
	end)
	eq(#results, 0)
	await(function()
		return #results == 1
	end)
	handle.cancel()
	eq(#results, 1)
	eq(results[1].status, "failed")
end

T["process"]["cancellation wins over a late process exit"] = function()
	config.setup({ bazel_cmd = "sh" })
	local results = {}
	local handle = cli.run(vim.fn.getcwd(), { "-c", "exec sleep 5" }, function(result)
		results[#results + 1] = result
	end)
	handle.cancel()
	await(function()
		return #results > 0
	end)
	eq(results[1].status, "cancelled")
	vim.wait(50, function()
		return #results > 1
	end)
	eq(#results, 1)
end

T["process"]["timeout is distinguishable from build failure"] = function()
	config.setup({ bazel_cmd = "sh" })
	local result
	cli.run(vim.fn.getcwd(), { "-c", "exec sleep 5" }, function(value)
		result = value
	end, { timeout = 20 })
	await(function()
		return result ~= nil
	end)
	eq(result.status, "timeout")
end

T["process"]["startup flags precede the verb and runtime arguments are preserved"] = function()
	config.setup({ startup_args = { "--output_base=/space here" }, command_args = { run = { "--config=dev" } } })
	eq(cli.command("/ws", { "run", "//:app", "--", "two words" }), {
		"bazel",
		"--output_base=/space here",
		"run",
		"--config=dev",
		"//:app",
		"--",
		"two words",
	})
end

T["python settings"] = MiniTest.new_set()

T["python settings"]["refresh retains user paths and removes only our old paths"] = function()
	local client = {
		name = "pyright",
		settings = { python = { analysis = { extraPaths = { "/user", "/shared" }, typeCheckingMode = "strict" } } },
		notify = function()
			return true
		end,
	}
	python.apply({ root = "/nonexistent" }, { paths = { "/shared", "/old" } }, client)
	table.insert(client.settings.python.analysis.extraPaths, "/later")
	python.apply({ root = "/nonexistent" }, { paths = { "/new" } }, client)
	eq(client.settings.python.analysis.extraPaths, { "/user", "/shared", "/later", "/new" })
	eq(client.settings.python.analysis.typeCheckingMode, "strict")
end

T["python settings"]["basedpyright uses its own namespace"] = function()
	local client = {
		name = "basedpyright",
		settings = { python = { pythonPath = "/python" } },
		notify = function()
			return true
		end,
	}
	python.apply({ root = "/nonexistent" }, { paths = { "/imports" } }, client)
	eq(client.settings.basedpyright.analysis.extraPaths, { "/imports" })
	eq(client.settings.python.pythonPath, "/python")
	eq(client.settings.python.analysis, nil)
end

T["ownership"] = MiniTest.new_set()

T["ownership"]["rejects foreign shared and unproven rootless clients"] = function()
	eq(util.owns({ root_dir = "/ws2" }, "/ws"), false)
	eq(util.owns({}, "/ws"), false)
	eq(util.owns({ root_dir = "/ws/service" }, "/ws"), true)
	eq(util.owns({ root_dir = "/ws", workspace_folders = { { uri = "file:///other" } } }, "/ws"), false)
end

local tmp
T["metadata"] = MiniTest.new_set({
	hooks = {
		pre_case = function()
			tmp = vim.fn.tempname()
			vim.fn.mkdir(tmp .. "/out/generated", "p")
		end,
		post_case = function()
			vim.fn.delete(tmp, "rf")
		end,
	},
})

T["metadata"]["maps a generated runfiles import to the output tree"] = function()
	vim.fn.writefile({ "VALUE = 1" }, tmp .. "/out/generated/value.py")
	local metadata, warning = python.paths({
		{
			version = 1,
			workspace = "_main",
			imports = { "_main/generated" },
			sources = {
				{ source = false, path = "out/generated/value.py", short_path = "generated/value.py" },
			},
		},
	}, tmp, tmp)
	eq(warning, nil)
	eq(metadata.paths, { tmp, tmp .. "/out/generated" })
end

T["metadata"]["missing generated artifacts yield partial discovery"] = function()
	local _, warning = python.paths({
		{
			version = 1,
			imports = { "_main/generated" },
			sources = {
				{ source = false, path = "out/generated/missing.py", short_path = "generated/missing.py" },
			},
		},
	}, tmp, tmp)
	eq(type(warning), "string")
end

T["metadata"]["unsupported venv providers are explicit"] = function()
	local metadata, warning = python.paths({ { version = 1, venv = true, imports = {}, sources = {} } }, tmp, tmp)
	eq(metadata, nil)
	eq(warning:find("venv_symlinks", 1, true) ~= nil, true)
end

local sync, original_list, original_snapshot, original_clients, original_notify
local discoveries, snapshots, client, applied
T["coordinator"] = MiniTest.new_set({
	hooks = {
		pre_case = function()
			tmp = vim.fn.tempname()
			vim.fn.mkdir(tmp, "p")
			vim.fn.writefile({}, tmp .. "/MODULE.bazel")
			package.loaded["bzl.sync"] = nil
			sync = require("bzl.sync")
			config.setup({
				sync = {
					cache = false,
					languages = { cpp = { enabled = false }, go = { enabled = false }, rust = { enabled = false } },
				},
			})
			original_list = require("bzl.targets").list
			original_snapshot = require("bzl.sync.cache").snapshot
			original_clients, original_notify = vim.lsp.get_clients, vim.notify
			vim.notify = function() end
			discoveries, applied = {}, {}
			snapshots = { version = 1 }
			client = { name = "pyright", root_dir = tmp }
			vim.lsp.get_clients = function()
				return { client }
			end
			require("bzl.targets").list = function(_, callback)
				callback({ { kind = "py_binary", label = "//:app" } })
			end
			require("bzl.sync.cache").snapshot = function(_, callback)
				callback(vim.deepcopy(snapshots))
			end
			sync.register("python", {
				clients = { pyright = true },
				detect = function()
					return true
				end,
				discover = function(ctx, callback)
					discoveries[#discoveries + 1] = { ctx = ctx, callback = callback }
				end,
				apply = function(_, metadata)
					applied[#applied + 1] = metadata.value
					return true
				end,
			})
		end,
		post_case = function()
			sync.cancel(tmp)
			require("bzl.targets").list = original_list
			require("bzl.sync.cache").snapshot = original_snapshot
			vim.lsp.get_clients, vim.notify = original_clients, original_notify
			config.setup()
			package.loaded["bzl.sync"] = nil
			vim.fn.delete(tmp, "rf")
		end,
	},
})

local function ready(value)
	return { status = "ready", metadata = { value = value, files = {} } }
end

T["coordinator"]["coalesces identical requests and completes all callers"] = function()
	local count = 0
	sync.start({ root = tmp }, function()
		count = count + 1
	end)
	sync.start({ root = tmp }, function()
		count = count + 1
	end)
	eq(#discoveries, 1)
	discoveries[1].callback(ready(1))
	await(function()
		return count == 2
	end)
	eq(applied, { 1 })
end

T["coordinator"]["superseded callbacks cannot overwrite the new scope"] = function()
	sync.start({ root = tmp, targets = { "//old/..." } })
	sync.start({ root = tmp, targets = { "//new/..." } })
	discoveries[2].callback(ready(2))
	discoveries[1].callback(ready(1))
	eq(applied, { 2 })
	eq(sync.status(tmp).scope, { "//new/..." })
end

T["coordinator"]["external build changes invalidate a result before application"] = function()
	local result
	sync.start({ root = tmp }, function(value)
		result = value
	end)
	snapshots.version = 2
	discoveries[1].callback(ready(1))
	await(function()
		return result ~= nil
	end)
	eq(result.status, "stale")
	eq(applied, {})
end

T["coordinator"]["late LSP attachment applies validated in-memory metadata"] = function()
	vim.lsp.get_clients = function()
		return {}
	end
	sync.start({ root = tmp })
	discoveries[1].callback(ready(1))
	eq(applied, {})
	sync.attach(client, tmp)
	eq(applied, { 1 })
end

T["coordinator"]["failed refresh leaves the current client's working configuration"] = function()
	sync.start({ root = tmp })
	discoveries[1].callback(ready(1))
	sync.start({ root = tmp })
	discoveries[2].callback({ status = "failed", message = "offline" })
	eq(applied, { 1 })
	eq(sync.status(tmp).adapters.python.status, "failed")
	sync.attach(client, tmp)
	eq(applied, { 1, 1 })
end

T["coordinator"]["invalidation rejects attachment validation already in flight"] = function()
	sync.start({ root = tmp })
	discoveries[1].callback(ready(1))
	local callback
	require("bzl.sync.cache").snapshot = function(_, done)
		callback = done
	end
	sync.attach(client, tmp)
	sync.invalidate(tmp)
	callback(snapshots)
	eq(applied, { 1 })
end

T["coordinator"]["workspaces sync independently"] = function()
	sync.start({ root = tmp })
	sync.start({ root = tmp .. "/other" })
	discoveries[2].callback(ready(2))
	discoveries[1].callback(ready(1))
	eq(applied, { 1 })
	eq(sync.status(tmp .. "/other").adapters.python.metadata.value, 2)
end

T["coordinator"]["cancellation rejects a later discovery result"] = function()
	local result
	sync.start({ root = tmp }, function(value)
		result = value
	end)
	eq(sync.cancel(tmp), true)
	discoveries[1].callback(ready(1))
	await(function()
		return result ~= nil
	end)
	eq(result.status, "cancelled")
	eq(applied, {})
end

return T

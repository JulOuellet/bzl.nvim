local T = MiniTest.new_set()
local model = require("bzl.python.model")
local lsp = require("bzl.python.lsp")
local eq = MiniTest.expect.equality

local function client(name, root, settings)
	return {
		name = name or "pyright",
		root_dir = root or "/ws",
		settings = settings or {},
		notifications = {},
		notify = function(self, method, params)
			table.insert(self.notifications, { method = method, params = params })
		end,
	}
end

T["lsp"] = MiniTest.new_set()

T["lsp"]["uses each server's namespace and keeps unrelated settings"] = function()
	for _, name in ipairs({ "pyright", "basedpyright" }) do
		local namespace = name == "pyright" and "python" or "basedpyright"
		local c = client(name, "/ws", { [namespace] = { analysis = { typeCheckingMode = "strict" } } })
		eq(lsp.apply(c, "/ws", { paths = { "/deps" }, interpreter = "/bazel/python" }), true)
		eq(c.settings[namespace].analysis.extraPaths, { "/deps" })
		eq(c.settings[namespace].analysis.typeCheckingMode, "strict")
		eq(c.settings.python.pythonPath, "/bazel/python")
		eq(c.notifications[1].method, "workspace/didChangeConfiguration")
		if name == "basedpyright" then
			eq(c.settings.python.analysis, nil)
		end
	end
end

T["lsp"]["removes stale managed paths and preserves user paths, including overlaps"] = function()
	local c = client("pyright", "/ws", { python = { analysis = { extraPaths = { "/user", "/overlap" } } } })
	lsp.apply(c, "/ws", { paths = { "/old", "/overlap" } })
	table.insert(c.settings.python.analysis.extraPaths, "/added-by-user")
	lsp.apply(c, "/ws", { paths = { "/new" } })
	eq(c.settings.python.analysis.extraPaths, { "/user", "/overlap", "/added-by-user", "/new" })
	lsp.apply(c, "/ws", { paths = {} })
	eq(c.settings.python.analysis.extraPaths, { "/user", "/overlap", "/added-by-user" })
end

T["lsp"]["preserves explicit interpreter settings and updates managed interpreters"] = function()
	local user = client("pyright", "/ws", { python = { pythonPath = "/user/python" } })
	local automatic = client()
	for _, interpreter in ipairs({ "/bazel/old", "/bazel/new" }) do
		lsp.apply(user, "/ws", { paths = {}, interpreter = interpreter })
		lsp.apply(automatic, "/ws", { paths = {}, interpreter = interpreter })
		eq(user.settings.python.pythonPath, "/user/python")
		eq(automatic.settings.python.pythonPath, interpreter)
	end
	lsp.apply(automatic, "/ws", { paths = {} })
	eq(automatic.settings.python.pythonPath, nil)
end

T["lsp"]["does not notify twice or mutate another client's shared settings"] = function()
	local settings = { python = { analysis = { extraPaths = { "/user" } } } }
	local a, b = client("pyright", "/ws", settings), client("pyright", "/other", settings)
	lsp.apply(a, "/ws", { paths = { "/deps" } })
	lsp.apply(a, "/ws", { paths = { "/deps" } })
	eq(#a.notifications, 1)
	eq(b.settings.python.analysis.extraPaths, { "/user" })
end

T["lsp"]["excludes foreign, shared and unidentifiable clients"] = function()
	local rootless = client()
	rootless.root_dir = nil
	local shared = client()
	shared.workspace_folders = { { uri = vim.uri_from_fname("/other"), name = "other" } }
	for _, c in ipairs({ client("pyright", "/ws2"), client("pyright", "/other"), client("other"), rootless, shared }) do
		eq(lsp.apply(c, "/ws", { paths = { "/deps" } }), false)
		eq(#c.notifications, 0)
	end
	eq(lsp.belongs(client("pyright", "/ws/service"), "/ws"), true)
end

T["lsp"]["identifies rootless clients through their attached buffers"] = function()
	local root = vim.fn.getcwd() .. "/tests/python_fixture"
	local buf = vim.api.nvim_create_buf(false, false)
	vim.api.nvim_buf_set_name(buf, root .. "/app.py")
	local c = client()
	c.root_dir = nil
	c.attached_buffers = { [buf] = true }
	eq(lsp.belongs(c, root), true)
	eq(lsp.belongs(c, "/other"), false)
	vim.api.nvim_buf_delete(buf, { force = true })
end

T["lsp"]["keeps rooted clients eligible after opening an external dependency"] = function()
	local buf = vim.api.nvim_create_buf(false, false)
	vim.api.nvim_buf_set_name(buf, "/external/dependency/source.py")
	local c = client()
	c.attached_buffers = { [buf] = true }
	eq(lsp.belongs(c, "/ws"), true)
	vim.api.nvim_buf_delete(buf, { force = true })
end

T["model"] = MiniTest.new_set()

T["model"]["rejects malformed and partial metadata"] = function()
	for _, text in ipairs({ "not JSON", "{}", '{"label":"//:app","imports":[]}' }) do
		local result, err = model.parse(text)
		eq(result, nil)
		eq(type(err), "string")
	end
end

T["model"]["resolves only selected imports, including generated and external sources"] = function()
	local tmp = vim.fn.tempname()
	local root, exec = tmp .. "/workspace", tmp .. "/execroot/_main"
	vim.fn.mkdir(root .. "/src", "p")
	vim.fn.mkdir(exec .. "/bazel-out/bin/src", "p")
	vim.fn.mkdir(exec .. "/external/chosen/site-packages", "p")
	vim.fn.mkdir(exec .. "/external/unrelated/site-packages", "p")
	vim.fn.writefile({ "VALUE = 1" }, exec .. "/bazel-out/bin/src/generated.py")
	local records = model.parse(vim.json.encode({
		label = "//:app",
		imports = { "_main/src", "chosen/site-packages" },
		roots = { { repo = "", path = "bazel-out/bin" }, { repo = "chosen", path = "external/chosen" } },
		generated = { "bazel-out/bin/src/generated.py" },
	}))
	local resolved, err = model.resolve(records, root, exec)
	eq(err, nil)
	eq(resolved.paths, {
		root,
		exec .. "/bazel-out/bin",
		root .. "/src",
		exec .. "/bazel-out/bin/src",
		exec .. "/external/chosen/site-packages",
	})
	vim.fn.delete(tmp, "rf")
end

T["model"]["fails when a generated source was not materialized"] = function()
	local result, err = model.resolve({ { generated = { "missing.py" } } }, "/ws", "/missing")
	eq(result, nil)
	eq(err:find("was not built", 1, true) ~= nil, true)
end

T["model"]["rejects incompatible runtimes instead of choosing one arbitrarily"] = function()
	local result, err = model.resolve({
		{ imports = {}, roots = {}, generated = {}, interpreter = "/python/a", version = "3.11" },
		{ imports = {}, roots = {}, generated = {}, interpreter = "/python/b", version = "3.12" },
	}, "/ws", "/exec")
	eq(result, nil)
	eq(err:find("different Python runtimes", 1, true) ~= nil, true)
end

return T

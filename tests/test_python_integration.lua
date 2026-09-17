local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local root = vim.fn.getcwd() .. "/tests/python_fixture"
local coordinator = require("bzl.sync")

local function request(client, ...)
	if vim.fn.has("nvim-0.11") == 1 then
		return client:request_sync(...)
	end
	return client.request_sync(...)
end

local function sync(flags)
	require("bzl.config").setup({ python = { targets = { "//:app" } }, build_flags = flags or {} })
	local done, result = false, nil
	coordinator.run(root, function(value)
		result, done = value, true
	end)
	assert(
		vim.wait(120000, function()
			return done
		end, 50),
		"Python sync timed out"
	)
	assert(result and result.languages.python and result.languages.python.model, "Python sync failed")
	return coordinator.get(root, "python")
end

local function has_path(paths, suffix)
	return vim.iter(paths):any(function(path)
		return vim.endswith(path, suffix)
	end)
end

T["configured Python sync"] = function()
	if vim.fn.executable(require("bzl.config").get().bazel_cmd) == 0 then
		MiniTest.skip("bazel not available")
	end
	local normal = sync()
	eq(normal.targets, 1)
	eq(has_path(normal.paths, "/generated"), true)
	eq(has_path(normal.paths, "/normal/site-packages"), true)
	eq(has_path(normal.paths, "/alternate/site-packages"), false)
	eq(
		vim.iter(normal.paths):any(function(path)
			return path:find("packaging/site%-packages$") ~= nil
		end),
		true
	)
	eq(normal.version, "3.12")
	eq(vim.fn.executable(normal.interpreter), 1)
	local alternate = sync({ "--define=python_variant=alternate" })
	eq(has_path(alternate.paths, "/alternate/site-packages"), true)
	eq(has_path(alternate.paths, "/normal/site-packages"), false)
	require("bzl.config").setup()
end

for _, name in ipairs({ "pyright", "basedpyright" }) do
	T[name .. " resolves generated and external imports after attaching"] = function()
		local command = vim.env["BZL_TEST_" .. name:upper()] or vim.fn.exepath(name .. "-langserver")
		if command == "" or vim.fn.executable(require("bzl.config").get().bazel_cmd) == 0 then
			MiniTest.skip(name .. " or bazel not available")
		end
		if not coordinator.get(root, "python") then
			sync()
		end
		vim.cmd.edit(root .. "/app.py")
		vim.bo.filetype = "python"
		local namespace = name == "pyright" and "python" or "basedpyright"
		local id = vim.lsp.start({
			name = name,
			cmd = { command, "--stdio" },
			root_dir = root,
			settings = { [namespace] = { analysis = { typeCheckingMode = "basic", diagnosticMode = "openFilesOnly" } } },
		})
		assert(id, "language server did not start")
		local client = vim.lsp.get_client_by_id(id)
		local ok, err = pcall(function()
			assert(
				vim.wait(15000, function()
					return client.initialized and client.settings[namespace].analysis.extraPaths ~= nil
				end, 50),
				"cached Python model was not applied on LspAttach"
			)
			for _, position in ipairs({
				{ line = 0, character = 7 },
				{ line = 1, character = 8 },
				{ line = 2, character = 8 },
			}) do
				local response = request(client, "textDocument/definition", {
					textDocument = { uri = vim.uri_from_fname(root .. "/app.py") },
					position = position,
				}, 15000, 0)
				assert(response and not response.err, "definition request failed")
				local locations = response.result
				assert(type(locations) == "table" and #locations > 0, "import did not resolve")
				local uri = locations[1].uri or locations[1].targetUri
				local suffix = ({
					[0] = "/generated/message.py",
					[1] = "/site-packages/external_lib/__init__.py",
					[2] = "/site-packages/packaging/__init__.py",
				})[position.line]
				eq(vim.endswith(vim.uri_to_fname(uri), suffix), true)
			end
		end)
		vim.lsp.stop_client(id, true)
		vim.cmd("enew!")
		require("bzl.config").setup()
		assert(ok, err)
	end
end

return T

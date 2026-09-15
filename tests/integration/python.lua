-- Run from examples/multilang with BZL_TEST_LSP pointing to a language server.
local plugin = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))))
vim.opt.runtimepath:append(plugin)
vim.opt.swapfile = false
local root = vim.fn.getcwd()
local name = vim.env.BZL_TEST_LSP_NAME or "pyright"
local binary = vim.env.BZL_TEST_LSP or "pyright-langserver"
local cache_dir = vim.fn.tempname()
require("bzl.sync.cache").directory = function()
	return cache_dir
end
local namespace = name == "basedpyright" and "basedpyright" or "python"
local baseline = root .. "/python/diagnostics"
require("bzl").setup({
	sync = { languages = {
		cpp = { enabled = false },
		go = { enabled = false },
		rust = { enabled = false },
	} },
})

local function await(predicate, message, timeout)
	assert(vim.wait(timeout or 60000, predicate, 20), message)
end

local received, buffers = {}, {}
for _, file in ipairs({
	"python/main.py",
	"python/generated_main.py",
	"python/src/acme/greeting.py",
	"python/diagnostics/type_error.py",
}) do
	local buf = vim.fn.bufadd(root .. "/" .. file)
	vim.fn.bufload(buf)
	vim.bo[buf].filetype = "python"
	buffers[file] = buf
end
vim.api.nvim_set_current_buf(buffers["python/main.py"])
local capabilities = vim.lsp.protocol.make_client_capabilities()
-- Use push diagnostics consistently across Neovim 0.11 and 0.12.
capabilities.textDocument.diagnostic = { dynamicRegistration = false }
local id = assert(vim.lsp.start({
	name = name,
	cmd = { binary, "--stdio" },
	root_dir = root,
	capabilities = capabilities,
	init_options = { disablePullDiagnostics = true },
	on_init = function()
		print(name .. ": initialized")
	end,
	on_exit = function(code)
		if code ~= 0 then
			print(name .. ": server exited " .. code)
		end
	end,
	settings = { [namespace] = { analysis = { extraPaths = { baseline }, diagnosticMode = "openFilesOnly" } } },
	handlers = {
		["textDocument/publishDiagnostics"] = function(err, result, ctx, conf)
			if result then
				received[result.uri] = result.diagnostics
			end
			vim.lsp.diagnostic.on_publish_diagnostics(err, result, ctx, conf)
		end,
	},
}))
local client = assert(vim.lsp.get_client_by_id(id))
for _, buf in pairs(buffers) do
	vim.lsp.buf_attach_client(buf, id)
end
local function has(file, code)
	for _, diagnostic in ipairs(received[vim.uri_from_bufnr(buffers[file])] or {}) do
		if diagnostic.code == code then
			return true
		end
	end
	return false
end

local ok, err = xpcall(function()
	await(function()
		return client.initialized
	end, "server did not initialize")
	await(function()
		return has("python/main.py", "reportMissingImports") and has("python/generated_main.py", "reportMissingImports")
	end, "expected unresolved first-party and generated imports before sync")
	local result
	require("bzl.sync").start({ root = root }, function(value)
		result = value
	end)
	await(function()
		return result ~= nil
	end, "sync timed out", 180000)
	assert(result.status == "ready", vim.inspect(result.entry and result.entry.adapters or result))
	await(function()
		for file, buf in pairs(buffers) do
			if not received[vim.uri_from_bufnr(buf)] or has(file, "reportMissingImports") then
				return false
			end
		end
		return has("python/diagnostics/type_error.py", "reportArgumentType")
	end, "sync must resolve imports without suppressing genuine type errors")
	assert(vim.tbl_contains(client.settings[namespace].analysis.extraPaths, baseline), "lost user extraPaths")
	local function definition(file, line, character, suffix)
		local response = assert(client:request_sync("textDocument/definition", {
			textDocument = { uri = vim.uri_from_bufnr(buffers[file]) },
			position = { line = line, character = character },
		}, 10000, buffers[file]))
		assert(not response.err, vim.inspect(response.err))
		local location = assert(response.result and response.result[1], "no definition for " .. file)
		local path = vim.uri_to_fname(location.uri or location.targetUri)
		assert(path:sub(-#suffix) == suffix, "wrong definition: " .. path)
	end
	definition("python/main.py", 0, 12, "/python/src/acme/greeting.py")
	definition("python/src/acme/greeting.py", 0, 18, "/packaging/version.py")
	definition("python/generated_main.py", 0, 8, "/python/generated/build_info.py")
	local hover = assert(client:request_sync("textDocument/hover", {
		textDocument = { uri = vim.uri_from_bufnr(buffers["python/main.py"]) },
		position = { line = 4, character = 12 },
	}, 10000, buffers["python/main.py"]))
	assert(
		hover.result and vim.inspect(hover.result.contents):find("name: str", 1, true),
		"hover did not resolve the function signature"
	)
	-- Simulate a fresh editor's coordinator; validated disk state must reapply.
	package.loaded["bzl.sync"] = nil
	client.settings[namespace].analysis.extraPaths = { baseline }
	require("bzl.sync").attach(client, root)
	await(function()
		return #client.settings[namespace].analysis.extraPaths > 1
	end, "disk cache did not restore paths")
	print(name .. ": import diagnostics, definitions, genuine type errors, user settings and cache restore passed")
end, debug.traceback)
client:stop(true)
vim.fn.delete(cache_dir, "rf")
if not ok then
	print(vim.inspect(received))
	error(err)
end

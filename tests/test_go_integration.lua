local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local root = vim.fn.getcwd() .. "/tests/go_fixture"
local sync = require("bzl.sync")

local function request(client, ...)
	if vim.fn.has("nvim-0.11") == 1 then
		return client:request_sync(...)
	end
	return client.request_sync(...)
end

T["gopls refreshes Bazel imports, generated sources and build flags"] = function()
	local command = vim.env.BZL_TEST_GOPLS or vim.fn.exepath("gopls")
	if
		command == ""
		or vim.fn.executable("go") == 0
		or vim.fn.executable(require("bzl.config").get().bazel_cmd) == 0
	then
		MiniTest.skip("gopls, Go or Bazel not available")
	end
	local id
	local function start()
		id = assert(vim.lsp.start({
			name = "gopls",
			cmd = { command },
			root_dir = root,
			settings = { gopls = { analyses = { unusedparams = true } } },
		}))
		local client = vim.lsp.get_client_by_id(id)
		assert(
			vim.wait(15000, function()
				return client.initialized
			end, 50),
			"gopls did not initialize"
		)
		return client
	end
	local function refresh(flags)
		require("bzl.config").setup({ build_flags = flags or {} })
		local done, result = false, nil
		sync.run(root, function(value)
			result, done = value, true
		end)
		assert(
			vim.wait(180000, function()
				return done
			end, 50),
			"Go sync timed out"
		)
		assert(result and result.languages.go and result.languages.go.model, vim.inspect(result))
		return sync.get(root, "go")
	end
	local function definition(client, character, suffix)
		local response = request(client, "textDocument/definition", {
			textDocument = { uri = vim.uri_from_fname(root .. "/app.go") },
			position = { line = 9, character = character },
		}, 60000, 0)
		assert(response and not response.err and response.result and #response.result > 0, vim.inspect(response))
		local uri = response.result[1].uri or response.result[1].targetUri
		eq(vim.endswith(vim.uri_to_fname(uri), suffix), true)
	end
	local ok, err = pcall(function()
		vim.cmd.edit(root .. "/app.go")
		vim.bo.filetype = "go"
		local client = start() -- First sync must work with an already running server.
		local normal = refresh()
		eq(client.settings.gopls.env.GOPACKAGESDRIVER, normal.driver)
		eq(client.settings.gopls.analyses.unusedparams, true)
		definition(client, 13, "/lib/lib.go")
		definition(client, 33, "/generated/message.go")
		definition(client, 54, "/normal/message.go")
		local binary = vim.system({ normal.driver, "file=" .. root .. "/cmd/main.go" }, {
			cwd = root,
			text = true,
			stdin = vim.json.encode({ mode = 159, tests = true }),
		}):wait()
		local valid, failure = require("bzl.go.driver").validate(binary)
		assert(valid, failure)

		local alternate = refresh({ "--define=go_variant=alternate" })
		eq(alternate.driver ~= normal.driver, true)
		definition(client, 54, "/alternate/message.go")
		-- Refreshing unchanged flags must also reload a live server.
		local repeated = refresh({ "--define=go_variant=alternate" })
		eq(repeated.driver ~= alternate.driver, true)
		definition(client, 54, "/alternate/message.go")

		local before = vim.deepcopy(client.settings)
		require("bzl.config").setup({ go = { driver_target = "//:missing_driver" } })
		local failed
		sync.run(root, function(result)
			failed = result
		end)
		assert(vim.wait(15000, function()
			return failed ~= nil
		end, 50))
		assert(failed.languages.go.error, "invalid driver target should fail")
		eq(sync.get(root, "go").driver, repeated.driver)
		eq(client.settings, before)
		require("bzl.config").setup({ build_flags = { "--define=go_variant=alternate" } })

		vim.lsp.stop_client(id, true)
		assert(vim.wait(5000, function()
			return vim.lsp.get_client_by_id(id) == nil
		end, 50))
		client = start()
		assert(
			vim.wait(15000, function()
				return client.settings.gopls.env and client.settings.gopls.env.GOPACKAGESDRIVER == repeated.driver
			end, 50),
			"Go model was not replayed on LspAttach"
		)
		definition(client, 33, "/generated/message.go")
		definition(client, 54, "/alternate/message.go")

		-- Real type errors remain visible after imports resolve.
		vim.api.nvim_buf_set_lines(0, 9, 10, false, { "\treturn 123" })
		assert(
			vim.wait(15000, function()
				for _, diagnostic in ipairs(vim.diagnostic.get(0)) do
					if
						diagnostic.message:find("123", 1, true)
						and diagnostic.severity == vim.diagnostic.severity.ERROR
					then
						return true
					end
				end
			end, 50),
			"gopls did not report the real type error"
		)
	end)
	if id then
		local client = vim.lsp.get_client_by_id(id)
		if client then
			vim.lsp.stop_client(id, true)
		end
	end
	vim.cmd("enew!")
	require("bzl.config").setup()
	assert(ok, err)
end

return T

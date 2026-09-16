local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local go = require("bzl.languages.go")
local driver = require("bzl.go.driver")

local function client(settings)
	return {
		name = "gopls",
		root_dir = "/ws",
		settings = settings or {},
		notifications = {},
		notify = function(self, method, params)
			table.insert(self.notifications, { method, params })
		end,
	}
end

T["preserves user settings and replaces only owned Go configuration"] = function()
	local original = {
		gopls = {
			env = { CUSTOM = "value" },
			workspaceFiles = { "**/BUILD", "custom.build" },
			analyses = { unusedparams = true },
		},
	}
	local c = client(original)
	eq(go.apply(c, "/ws", { driver = "/first" }), true)
	table.insert(c.settings.gopls.workspaceFiles, "added.build")
	go.apply(c, "/ws", { driver = "/second" })
	eq(c.settings.gopls.env, { CUSTOM = "value", GOPACKAGESDRIVER = "/second" })
	eq(c.settings.gopls.analyses, { unusedparams = true })
	eq(original.gopls.env.GOPACKAGESDRIVER, nil)
	go.apply(c, "/ws", {})
	eq(c.settings.gopls.env, { CUSTOM = "value" })
	eq(c.settings.gopls.workspaceFiles, { "**/BUILD", "custom.build", "added.build" })
	go.apply(c, "/ws", {})
	eq(#c.notifications, 3)
end

T["respects explicit drivers and user changes to managed drivers"] = function()
	for _, configured in ipairs({ "/custom", "off" }) do
		local c = client({ gopls = { env = { GOPACKAGESDRIVER = configured } } })
		local applied, note = go.apply(c, "/ws", { driver = "/ours" })
		eq(applied, false)
		eq(type(note), "string")
		eq(#c.notifications, 0)
	end
	local c = client()
	go.apply(c, "/ws", { driver = "/ours" })
	c.settings.gopls.env.GOPACKAGESDRIVER = "/user-edit"
	eq(go.apply(c, "/ws", { driver = "/new" }), false)
	eq(c.settings.gopls.env.GOPACKAGESDRIVER, "/user-edit")
	local inherited = client()
	inherited.config = { cmd_env = { GOPACKAGESDRIVER = "/inherited" } }
	eq(go.apply(inherited, "/ws", { driver = "/ours" }), false)
end

T["excludes foreign and shared clients"] = function()
	local foreign, shared, other = client(), client(), client()
	foreign.root_dir = "/ws2"
	shared.workspace_folders = { { uri = vim.uri_from_fname("/other") } }
	other.name = "pyright"
	for _, c in ipairs({ foreign, shared, other }) do
		eq(go.apply(c, "/ws", { driver = "/ours" }), false)
		eq(#c.notifications, 0)
	end
end

T["rejects invalid driver responses even with exit code zero"] = function()
	for _, response in ipairs({
		"",
		"null",
		"{}",
		"not JSON",
		'{"NotHandled":true}',
		'{"Roots":[],"Packages":[]}',
		'{"Roots":["missing"],"Packages":[{"ID":"app"}]}',
		'{"Roots":["app"],"Packages":[false]}',
	}) do
		local valid, err = driver.validate({ code = 0, stdout = response, stderr = "driver error" })
		eq(valid, nil)
		eq(type(err), "string")
	end
	eq(driver.validate({ code = 0, stdout = '{"Roots":["app"],"Packages":[{"ID":"app"}]}' }), true)
end

T["does not configure a client spanning nested Bazel workspaces"] = function()
	local root = vim.fn.tempname()
	vim.fn.mkdir(root .. "/nested", "p")
	vim.fn.writefile({}, root .. "/MODULE.bazel")
	vim.fn.writefile({}, root .. "/nested/MODULE.bazel")
	local c = client()
	c.root_dir = root
	c.workspace_folders = { { uri = vim.uri_from_fname(root .. "/nested") } }
	eq(go.apply(c, root, { driver = "/ours" }), false)
	vim.fn.delete(root, "rf")
end

T["launcher preserves argv, stdin and the caller's working directory"] = function()
	if vim.fn.has("win32") == 1 then
		MiniTest.skip("POSIX launcher")
	end
	local directory = vim.fn.tempname() .. " space's"
	vim.fn.mkdir(directory .. "/sub", "p")
	local executable = directory .. "/capture"
	vim.fn.writefile({
		"#!/bin/sh",
		'printf "%s\\n" "$BUILD_WORKSPACE_DIRECTORY" "$BUILD_WORKING_DIRECTORY" "$PWD" "$@"',
		'"$GOPACKAGESDRIVER_BAZEL" build "caller arg"',
		'"$GOPACKAGESDRIVER_BAZEL" query "query arg"',
		"cat",
	}, executable)
	assert(vim.uv.fs_chmod(executable, 448))
	local bazel = directory .. "/fake bazel"
	vim.fn.writefile({ "#!/bin/sh", 'printf "<%s>\\n" "$@"' }, bazel)
	assert(vim.uv.fs_chmod(bazel, 448))
	local config =
		{ bazel_cmd = bazel, startup_flags = { "--output_base=a b", "quote's" }, build_flags = { "--define=a=b c" } }
	local launcher = driver.create(directory, config, executable)
	local ok, err = pcall(function()
		local result = vim.system(
			{ launcher, "file=space's.go" },
			{ cwd = directory .. "/sub", stdin = "protocol input", text = true }
		):wait()
		eq(result.code, 0)
		eq(
			result.stdout,
			table.concat({
				directory,
				directory .. "/sub",
				directory,
				"file=space's.go",
				"<--output_base=a b>",
				"<quote's>",
				"<build>",
				"<--define=a=b c>",
				"<--remote_download_outputs=all>",
				"<caller arg>",
				"<--output_base=a b>",
				"<quote's>",
				"<query>",
				"<query arg>",
				"protocol input",
			}, "\n")
		)
	end)
	vim.fn.delete(directory, "rf")
	assert(ok, err)
end

return T

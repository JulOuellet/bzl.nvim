-- Run from examples/multilang; exercises the actual rules_go JSON protocol.
local plugin = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2))))
vim.opt.runtimepath:append(plugin)
local root = vim.fn.getcwd()
local directory = vim.fn.tempname()
require("bzl.sync.cache").directory = function()
	return directory
end
require("bzl").setup({
	sync = {
		languages = {
			python = { enabled = false },
			cpp = { enabled = false },
			rust = { enabled = false },
		},
	},
})
local ok, err = xpcall(function()
	local result
	require("bzl.sync").start({ root = root, targets = { "//go/..." } }, function(value)
		result = value
	end)
	assert(
		vim.wait(180000, function()
			return result ~= nil
		end, 20),
		"Go sync timed out"
	)
	assert(result.status == "ready", vim.inspect(result.entry and result.entry.adapters or result))
	local driver = result.entry.adapters.go.metadata.driver
	local response = vim.system({ driver, "file=" .. root .. "/go/main.go" }, {
		cwd = root,
		text = true,
		stdin = vim.json.encode({ mode = 159, tests = false }),
		timeout = 180000,
	}):wait()
	assert(response.code == 0, response.stderr)
	local decoded, packages = pcall(vim.json.decode, response.stdout)
	assert(decoded and type(packages) == "table", "driver returned invalid JSON: " .. response.stderr)
	assert(
		not packages.NotHandled and #(packages.Roots or {}) > 0,
		"driver returned no root packages: " .. response.stderr
	)
	local found = false
	for _, package in ipairs(packages.Packages or {}) do
		if package.PkgPath == "example.com/bzl-multilang/greeting" then
			assert(#(package.GoFiles or {}) > 0, "dependency has no source files")
			found = true
		end
	end
	assert(found, "driver did not resolve the Bazel-only dependency")
	print("go: package-driver protocol resolved the local Bazel dependency")
end, debug.traceback)
vim.fn.delete(directory, "rf")
if not ok then
	error(err)
end

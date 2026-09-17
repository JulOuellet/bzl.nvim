local M = {}

local function quote(value)
	return "'" .. value:gsub("'", "'\\''") .. "'"
end

---Use argv-preserving wrappers: rules_go splits its flag environment variables
---on whitespace, which would otherwise corrupt flags containing spaces.
function M.create(root, config, executable)
	local directory = vim.fn.tempname()
	vim.fn.mkdir(directory, "p", 448)
	local bazel, driver = directory .. "/bazel", directory .. "/driver"
	local commands = { "#!/bin/sh", 'case "$1" in' }
	for _, verb in ipairs({ "query", "build", "info" }) do
		local args = { verb }
		if verb == "build" then
			args[#args + 1] = "--remote_download_outputs=all"
		end
		local argv = require("bzl.cli").command(args, config)
		commands[#commands + 1] = verb .. ") shift; exec " .. table.concat(vim.tbl_map(quote, argv), " ") .. ' "$@" ;;'
	end
	commands[#commands + 1] = '*) echo "Unsupported Bazel package-driver command: $1" >&2; exit 1 ;;'
	commands[#commands + 1] = "esac"
	local launcher = {
		"#!/bin/sh",
		'export BUILD_WORKING_DIRECTORY="$PWD"',
		"export BUILD_WORKSPACE_DIRECTORY=" .. quote(root),
		"export GOPACKAGESDRIVER_BAZEL=" .. quote(bazel),
		"unset GOPACKAGESDRIVER_BAZEL_FLAGS GOPACKAGESDRIVER_BAZEL_COMMON_FLAGS",
		"unset GOPACKAGESDRIVER_BAZEL_QUERY_FLAGS GOPACKAGESDRIVER_BAZEL_BUILD_FLAGS",
		"cd " .. quote(root) .. " || exit 1",
		"exec " .. quote(executable) .. ' "$@"',
	}
	for path, lines in pairs({ [bazel] = commands, [driver] = launcher }) do
		assert(vim.fn.writefile(lines, path) == 0, "could not write Go driver launcher")
		assert(vim.uv.fs_chmod(path, 448))
	end
	-- Each successful sync has a distinct driver path, so gopls reloads even
	-- when the Bazel flags are unchanged. Neovim removes these files on exit.
	return driver
end

---Some rules_go versions exit successfully on errors, so validate the protocol.
function M.validate(result)
	local ok, response = pcall(vim.json.decode, result.stdout or "")
	if result.code ~= 0 or not ok or type(response) ~= "table" or response.NotHandled then
		return nil, "Go package driver failed:\n" .. (result.stderr or "invalid driver response")
	end
	for _, field in ipairs({ "Roots", "Packages" }) do
		if type(response[field]) ~= "table" or not vim.islist(response[field]) or #response[field] == 0 then
			return nil, "Go package driver returned no " .. field .. ":\n" .. (result.stderr or "")
		end
	end
	local packages = {}
	for _, package in ipairs(response.Packages) do
		if type(package) ~= "table" or type(package.ID) ~= "string" then
			return nil, "Go package driver returned an invalid package"
		end
		packages[package.ID] = true
	end
	for _, root in ipairs(response.Roots) do
		if type(root) ~= "string" or not packages[root] then
			return nil, "Go package driver returned an unresolved root package"
		end
	end
	return true
end

return M

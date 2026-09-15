local util = require("bzl.languages.util")
local M = { clients = { gopls = true } }

function M.detect(ctx)
	return util.has_kind(ctx, "^go_")
end

function M.discover(ctx, done)
	if vim.fn.has("win32") == 1 then
		done({ status = "unsupported", message = "Go driver launcher currently requires a POSIX shell" })
		return
	end
	local target = ctx.config.sync.languages.go.driver_target
	ctx.run({ "build", target }, function(result)
		if result.code ~= 0 then
			done(util.failed(result))
			return
		end
		local directory = require("bzl.sync.cache").directory()
		vim.fn.mkdir(directory, "p", 448)
		local driver = directory .. "/" .. ctx.key .. "-gopackagesdriver"
		local bazel = driver .. "-bazel"
		local wrapper = { "#!/bin/sh", 'case "$1" in' }
		for _, verb in ipairs({ "info", "query", "build" }) do
			local command = require("bzl.cli").command(ctx.root, { verb }, ctx.config)
			wrapper[#wrapper + 1] = verb
				.. ") shift; exec "
				.. table.concat(vim.tbl_map(vim.fn.shellescape, command), " ")
				.. ' "$@" ;;'
		end
		wrapper[#wrapper + 1] = '*) echo "Unsupported package-driver Bazel command" >&2; exit 1 ;;'
		wrapper[#wrapper + 1] = "esac"
		local argv = require("bzl.cli").command(ctx.root, { "run", target, "--" }, ctx.config)
		local command = table.concat(vim.tbl_map(vim.fn.shellescape, argv), " ")
		local lines = {
			"#!/bin/sh",
			"cd " .. vim.fn.shellescape(ctx.root) .. " || exit 1",
			-- Upstream splits flag variables on whitespace. A wrapper preserves argv.
			"export GOPACKAGESDRIVER_BAZEL=" .. vim.fn.shellescape(bazel),
			"export GOPACKAGESDRIVER_BAZEL_FLAGS='' GOPACKAGESDRIVER_BAZEL_COMMON_FLAGS=''",
			"export GOPACKAGESDRIVER_BAZEL_QUERY_FLAGS='' GOPACKAGESDRIVER_BAZEL_BUILD_FLAGS=''",
			"exec " .. command .. ' "$@"',
		}
		local ok, err = pcall(function()
			for path, contents in pairs({ [bazel] = wrapper, [driver] = lines }) do
				local tmp = path .. ".tmp"
				assert(vim.fn.writefile(contents, tmp) == 0)
				assert(vim.uv.fs_chmod(tmp, 448))
				assert(vim.uv.fs_rename(tmp, path))
			end
		end)
		if not ok then
			done({ status = "failed", message = tostring(err) })
			return
		end
		done(util.result({
			driver = driver,
			files = { driver, bazel },
			fingerprints = {
				[driver] = require("bzl.sync.cache").stamp(driver),
				[bazel] = require("bzl.sync.cache").stamp(bazel),
			},
		}, "Bazel package driver ready; package loading may build Go metadata"))
	end)
end

function M.apply(_, metadata, client)
	client.settings = vim.deepcopy(client.settings or {})
	client.settings.gopls = client.settings.gopls or {}
	local settings = client.settings.gopls
	settings.env = settings.env or {}
	if
		settings.env.GOPACKAGESDRIVER
		and settings.env.GOPACKAGESDRIVER ~= client._bzl_go_driver
		and settings.env.GOPACKAGESDRIVER ~= metadata.driver
	then
		return false, "Preserved user GOPACKAGESDRIVER; remove it to use bzl.nvim's driver"
	end
	settings.env.GOPACKAGESDRIVER = metadata.driver
	client._bzl_go_driver = metadata.driver
	settings.workspaceFiles = util.merge_paths(
		client,
		"go-files",
		settings.workspaceFiles,
		{ "**/BUILD", "**/*.bazel", "**/*.bzl", "**/WORKSPACE" }
	)
	return client:notify("workspace/didChangeConfiguration", { settings = client.settings }) ~= false
end

return M

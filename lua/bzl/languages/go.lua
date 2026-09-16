local M = {}
local managed = setmetatable({}, { __mode = "k" })
local workspace_files = {
	"**/BUILD",
	"**/*.bazel",
	"**/*.bzl",
	"**/WORKSPACE",
	"**/WORKSPACE.bazel",
	"**/MODULE.bazel.lock",
	"**/.bazelrc",
}

function M.detect(ctx)
	for _, target in ipairs(ctx.targets) do
		if target.kind:match("^go_") then
			return true
		end
	end
	return false
end

function M.prepare(ctx, done)
	if not M.detect(ctx) then
		done({ summary = "no Go targets" })
		return
	end
	if vim.fn.has("win32") == 1 then
		done(nil, "Go sync currently requires a POSIX shell")
		return
	end
	local target = ctx.config.go.driver_target
	if type(target) ~= "string" or not target:match("^[@/]") or target:find("[%s\"'()]") then
		done(nil, "invalid go.driver_target")
		return
	end
	vim.notify("bzl.nvim: preparing Go package driver...", vim.log.levels.INFO)
	ctx.run({ "build", "--remote_download_outputs=all", target }, function()
		ctx.run({ "cquery", target, "--output=files" }, function(output)
			local files = vim.split(vim.trim(output), "\n", { trimempty = true })
			if #files ~= 1 then
				done(nil, "go.driver_target must produce exactly one executable")
				return
			end
			ctx.run({ "info", "execution_root" }, function(info)
				local execution_root = vim.trim(info)
				if execution_root:sub(1, 1) ~= "/" then
					done(nil, "bazel info returned an invalid execution_root")
					return
				end
				local executable = files[1]:sub(1, 1) == "/" and files[1] or (execution_root .. "/" .. files[1])
				if vim.fn.executable(executable) ~= 1 then
					done(nil, "Go package driver executable was not built: " .. executable)
					return
				end
				local ok, driver = pcall(require("bzl.go.driver").create, ctx.root, ctx.config, executable)
				if not ok then
					done(nil, driver)
					return
				end
				-- Loading std validates the driver/toolchain without scanning the entire
				-- Go workspace. gopls subsequently requests the packages it needs.
				local started, err = pcall(
					vim.system,
					{ driver, "std" },
					{
						cwd = ctx.root,
						text = true,
						stdin = vim.json.encode({ mode = 159, tests = false }),
					},
					vim.schedule_wrap(function(result)
						local valid, failure = require("bzl.go.driver").validate(result)
						if valid then
							done({ driver = driver, summary = "package driver ready" })
						else
							done(nil, failure)
						end
					end)
				)
				if not started then
					done(nil, "could not start Go package driver: " .. tostring(err))
				end
			end)
		end)
	end)
end

function M.apply(client, root, model)
	if client.name ~= "gopls" or not require("bzl.lsp").belongs(client, root) then
		return false
	end
	local settings = vim.deepcopy(client.settings or {})
	settings.gopls = settings.gopls or {}
	local opts = settings.gopls
	opts.env = opts.env or {}
	local previous = managed[client] or { added = {} }
	local current = opts.env.GOPACKAGESDRIVER
	local inherited = (client.config and client.config.cmd_env or {}).GOPACKAGESDRIVER or vim.env.GOPACKAGESDRIVER
	if (current and current ~= previous.driver) or (not current and inherited and inherited ~= "") then
		return false, "preserved user GOPACKAGESDRIVER; gopls was not changed"
	end
	opts.env.GOPACKAGESDRIVER = model.driver
	local patterns = {}
	for _, pattern in ipairs(opts.workspaceFiles or {}) do
		if not previous.added[pattern] then
			patterns[#patterns + 1] = pattern
		end
	end
	local added = {}
	if model.driver then
		for _, pattern in ipairs(workspace_files) do
			if not vim.tbl_contains(patterns, pattern) then
				patterns[#patterns + 1] = pattern
				added[pattern] = true
			end
		end
	end
	opts.workspaceFiles = patterns
	managed[client] = { driver = model.driver, added = added }
	if not vim.deep_equal(settings, client.settings) then
		client.settings = settings
		client:notify("workspace/didChangeConfiguration", { settings = settings })
	end
	return true
end

return M

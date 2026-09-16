local M = {}

local models, running, generations = {}, {}, {}
local query_file = vim.fs.joinpath(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)), "../../bazel/python.cquery")

---Retain the last successful model, but never publish results from before an edit.
function M.invalidate(root)
	if root then
		generations[root] = (generations[root] or 0) + 1
	end
end

function M.attach(client)
	local lsp = require("bzl.python.lsp")
	for root, model in pairs(models) do
		if lsp.apply(client, root, model) then
			return
		end
	end
end

---Return the last successful model for health checks and integrations.
function M.get(root)
	return models[root] and vim.deepcopy(models[root]) or nil
end

---Analyze selected Python targets, build their outputs, then publish atomically.
---@param root string|nil
---@param on_done fun(result: table|nil)
---@param targets bzl.Target[]|nil previously queried workspace targets
function M.sync(root, on_done, targets)
	local cli = require("bzl.cli")
	if not root then
		vim.notify("bzl.nvim: no bazel workspace found", vim.log.levels.ERROR)
		on_done(nil)
		return
	end
	if running[root] then
		vim.notify("bzl.nvim: Python sync already running for " .. root, vim.log.levels.WARN)
		on_done(nil)
		return
	end
	running[root] = true
	local config = vim.deepcopy(require("bzl.config").get())
	local generation = generations[root] or 0
	local finished = false
	local function finish(model, err)
		if finished then
			return
		end
		finished = true
		running[root] = nil
		if generation ~= (generations[root] or 0) then
			model, err = nil, "build files changed during sync; run :Bzl sync again"
		end
		local current = require("bzl.config").get()
		for _, key in ipairs({ "bazel_cmd", "startup_flags", "build_flags", "python" }) do
			if not vim.deep_equal(config[key], current[key]) then
				model, err = nil, "Bazel configuration changed during sync; run :Bzl sync again"
			end
		end
		if not model then
			vim.notify("bzl.nvim: Python sync failed; previous LSP configuration kept.\n" .. err, vim.log.levels.ERROR)
			on_done(nil)
			return
		end
		models[root] = model
		local clients = 0
		for _, client in ipairs(vim.lsp.get_clients()) do
			if require("bzl.python.lsp").apply(client, root, model) then
				clients = clients + 1
			end
		end
		on_done({ paths = #model.paths, clients = clients, targets = model.targets })
	end
	local function run(args, callback)
		if generation ~= (generations[root] or 0) then
			finish(nil, "build files changed during sync")
			return
		end
		local started = cli.run(root, args, function(result)
			if result.code ~= 0 then
				finish(nil, "bazel " .. args[1] .. " failed:\n" .. (result.stderr or ""))
			else
				callback(result.stdout or "")
			end
		end, config)
		if not started then
			finish(nil, "could not start bazel " .. args[1])
		end
	end

	local function analyze(labels)
		if #labels == 0 then
			finish({ paths = {}, targets = 0 })
			return
		end
		for _, label in ipairs(labels) do
			if type(label) ~= "string" or not label:match("^[@/]") or label:find("[%s\"'()]") then
				finish(nil, "invalid Python target pattern: " .. tostring(label))
				return
			end
		end
		local expression = "config(set(" .. table.concat(labels, " ") .. "), target)"
		run({ "cquery", expression, "--output=starlark", "--starlark:file=" .. query_file }, function(output)
			local records, err = require("bzl.python.model").parse(output)
			if not records or #records == 0 then
				finish(nil, err or "selected targets do not expose PyInfo")
				return
			end
			vim.notify(("bzl.nvim: building %d Python targets..."):format(#records), vim.log.levels.INFO)
			local build = { "build", "--output_groups=+compilation_outputs", "--remote_download_outputs=all" }
			for _, record in ipairs(records) do
				build[#build + 1] = record.label
			end
			run(build, function()
				run({ "info", "execution_root" }, function(info)
					local execution_root = vim.trim(info)
					if execution_root == "" or execution_root:sub(1, 1) ~= "/" then
						finish(nil, "bazel info returned an invalid execution_root")
						return
					end
					local model, resolve_err = require("bzl.python.model").resolve(records, root, execution_root)
					finish(model, resolve_err)
				end)
			end)
		end)
	end

	local configured = config.python.targets
	if #configured > 0 then
		analyze(configured)
	else
		local function from_targets(list)
			if not list then
				finish(nil, "target discovery failed")
				return
			end
			local labels = {}
			for _, target in ipairs(list) do
				if target.kind:match("^py_") then
					labels[#labels + 1] = target.label
				end
			end
			table.sort(labels)
			analyze(labels)
		end
		if targets then
			from_targets(targets)
		else
			require("bzl.targets").list(root, from_targets, { refresh = true })
		end
	end
end

return M

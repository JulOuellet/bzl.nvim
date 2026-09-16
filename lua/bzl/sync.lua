local M = {}
local languages = { "python", "go" }
local models, running, generations = {}, {}, {}

function M.invalidate(root)
	if root then
		generations[root] = (generations[root] or 0) + 1
	end
end

function M.get(root, language)
	local model = models[root] and models[root][language]
	return model and vim.deepcopy(model) or nil
end

function M.attach(client)
	for root, saved in pairs(models) do
		for name, model in pairs(saved) do
			if require("bzl.config").get()[name].enabled then
				require("bzl.languages." .. name).apply(client, root, model)
			end
		end
	end
end

---One refresh per workspace. Adapters own their metadata and LSP settings.
---prepare(ctx, done) returns a model (with a summary) or nil, error.
---ctx.run runs Bazel with the captured configuration and reports errors for the adapter.
function M.run(root, on_done)
	if not root then
		vim.notify("bzl.nvim: no bazel workspace found", vim.log.levels.ERROR)
		on_done(nil)
		return
	end
	if running[root] then
		vim.notify("bzl.nvim: sync already running for " .. root, vim.log.levels.WARN)
		on_done(nil)
		return
	end
	running[root] = true
	local config = vim.deepcopy(require("bzl.config").get())
	local generation = generations[root] or 0
	local result = { targets = 0, languages = {} }
	local finished = false
	local function stale()
		if generation ~= (generations[root] or 0) then
			return "build files changed during sync; run :Bzl sync again"
		end
		local current = require("bzl.config").get()
		for _, key in ipairs({ "bazel_cmd", "startup_flags", "build_flags", "python", "go" }) do
			if not vim.deep_equal(config[key], current[key]) then
				return "Bazel configuration changed during sync; run :Bzl sync again"
			end
		end
	end
	local function finish(err)
		if finished then
			return
		end
		finished, running[root] = true, nil
		err = stale() or err
		if err then
			vim.notify("bzl.nvim: sync failed; previous LSP configuration kept.\n" .. err, vim.log.levels.ERROR)
			on_done(nil)
			return
		end
		models[root] = models[root] or {}
		for _, name in ipairs(languages) do
			local entry = result.languages[name]
			if entry and entry.model then
				models[root][name] = entry.model
				entry.clients = 0
				for _, client in ipairs(vim.lsp.get_clients()) do
					local applied, note = require("bzl.languages." .. name).apply(client, root, entry.model)
					if applied then
						entry.clients = entry.clients + 1
					elseif note then
						vim.notify("bzl.nvim: " .. note, vim.log.levels.WARN)
					end
				end
			elseif entry then
				vim.notify(
					"bzl.nvim: " .. name .. " sync failed; previous LSP configuration kept.\n" .. entry.error,
					vim.log.levels.ERROR
				)
			end
		end
		on_done(result)
	end

	require("bzl.targets").list(root, function(targets)
		if not targets then
			finish("target discovery failed")
			return
		end
		result.targets = #targets
		local function next_adapter(index)
			local err = stale()
			if err or index > #languages then
				finish(err)
				return
			end
			local name = languages[index]
			local adapter = require("bzl.languages." .. name)
			local ctx = { root = root, config = config, targets = targets }
			if not config[name].enabled or not (adapter.detect(ctx) or (models[root] and models[root][name])) then
				next_adapter(index + 1)
				return
			end
			local completed = false
			local function done(model, failure)
				if completed then
					return
				end
				completed = true
				result.languages[name] = { model = model, error = failure }
				next_adapter(index + 1)
			end
			function ctx.run(args, callback)
				local changed = stale()
				if changed then
					done(nil, changed)
					return
				end
				local started = require("bzl.cli").run(root, args, function(output)
					if completed then
						return
					end
					if output.code ~= 0 then
						done(nil, "bazel " .. args[1] .. " failed:\n" .. (output.stderr or ""))
					else
						callback(output.stdout or "")
					end
				end, config)
				if not started then
					done(nil, "could not start bazel " .. args[1])
				end
			end
			adapter.prepare(ctx, done)
		end
		next_adapter(1)
	end, { refresh = true })
end

return M

local M = {}
local util = require("bzl.languages.util")
local cache = require("bzl.sync.cache")
local states, running, adapters, generations, available = {}, {}, {}, {}, {}

function M.register(name, adapter)
	assert(
		type(adapter.detect) == "function"
			and type(adapter.discover) == "function"
			and type(adapter.apply) == "function",
		"invalid sync adapter"
	)
	adapters[name] = adapter
end

local function get_adapters()
	for _, name in ipairs({ "python", "cpp", "go", "rust" }) do
		if not adapters[name] then
			adapters[name] = require("bzl.languages." .. name)
		end
	end
	return adapters
end

function M.context(root, scope)
	root = root or require("bzl.cli").workspace_root()
	if not root then
		return nil
	end
	root = vim.fs.normalize(root)
	local config = vim.deepcopy(require("bzl.config").get(root))
	local ctx =
		{ root = root, config = config, scope = scope and #scope > 0 and vim.deepcopy(scope) or config.sync.targets }
	ctx.key = cache.key(ctx)
	return ctx
end

local function bind(ctx, job)
	function job.cleanup()
		if (job.pending or 0) == 0 then
			for _, cleanup in ipairs(job.cleanups) do
				pcall(cleanup)
			end
			job.cleanups = {}
		end
	end
	function ctx.cleanup(fn)
		job.cleanups[#job.cleanups + 1] = fn
	end
	function ctx.run(args, callback)
		if job.done then
			return
		end
		local timeout = (args[1] == "query" or args[1] == "info") and ctx.config.sync.query_timeout
			or ctx.config.sync.build_timeout
		job.pending = (job.pending or 0) + 1
		local handle = require("bzl.cli").run(ctx.root, args, function(result)
			job.pending = job.pending - 1
			if not job.done then
				callback(result)
			else
				job.cleanup()
			end
		end, { config = ctx.config, timeout = timeout })
		job.handles[#job.handles + 1] = handle
		return handle
	end
end

local function apply(ctx, entry, client)
	local results = {}
	for name, result in pairs(entry.adapters) do
		local adapter, opts = get_adapters()[name], ctx.config.sync.languages[name]
		if adapter and opts and opts.enabled and result.status == "ready" and result.metadata then
			local count, notes = 0, {}
			for _, item in ipairs(client and { client } or vim.lsp.get_clients()) do
				if (adapter.clients or {})[item.name] and util.owns(item, ctx.root) then
					local ok, applied, note = pcall(adapter.apply, ctx, result.metadata, item)
					if ok and applied then
						count = count + 1
					else
						notes[#notes + 1] = ok and (note or "not applied") or tostring(applied)
					end
				end
			end
			results[name] = { clients = count, notes = notes }
		end
	end
	return results
end

function M.cancel(root)
	root = root or require("bzl.cli").workspace_root()
	local job = root and running[root]
	if not job then
		return false
	end
	job.finish({ status = "cancelled", root = root })
	for _, handle in ipairs(job.handles) do
		if handle and handle.cancel then
			handle.cancel()
		end
	end
	require("bzl.targets").refresh(root)
	return true
end

function M.invalidate(root)
	if not root then
		return
	end
	M.cancel(root)
	generations[root] = (generations[root] or 0) + 1
	states[root] = nil
	available[root] = nil
	require("bzl.targets").refresh(root)
end

function M.status(root)
	root = root or require("bzl.cli").workspace_root()
	return root and states[root] or nil
end

---Explicit sync refreshes metadata. Identical in-flight requests coalesce.
function M.start(opts, on_done)
	opts = opts or {}
	local ctx = M.context(opts.root, opts.targets)
	if not ctx then
		vim.notify("bzl.nvim: no bazel workspace found", vim.log.levels.ERROR)
		if on_done then
			vim.schedule(function()
				on_done({ status = "failed" })
			end)
		end
		return
	end
	local previous = running[ctx.root]
	if previous and previous.key == ctx.key then
		if on_done then
			previous.callbacks[#previous.callbacks + 1] = on_done
		end
		return previous
	end
	M.cancel(ctx.root)
	generations[ctx.root] = (generations[ctx.root] or 0) + 1
	local job = { key = ctx.key, handles = {}, cleanups = {}, callbacks = on_done and { on_done } or {} }
	running[ctx.root] = job
	local started = vim.uv.hrtime()
	function job.finish(result)
		if job.done then
			return
		end
		job.done = true
		if running[ctx.root] == job then
			running[ctx.root] = nil
		end
		job.cleanup()
		for _, callback in ipairs(job.callbacks) do
			vim.schedule(function()
				callback(result)
			end)
		end
	end
	bind(ctx, job)
	vim.notify("bzl.nvim: syncing targets and language metadata...", vim.log.levels.INFO)
	require("bzl.targets").list(ctx.root, function(targets)
		if job.done then
			return
		end
		if not targets then
			job.finish({ status = "failed" })
			return
		end
		ctx.targets = targets
		cache.snapshot(ctx, function(before, err)
			if not before then
				vim.notify("bzl.nvim: cannot read build inputs: " .. (err or ""), vim.log.levels.ERROR)
				job.finish({ status = "failed" })
				return
			end
			local entry = {
				version = cache.version,
				key = ctx.key,
				root = ctx.root,
				scope = ctx.scope,
				adapters = {},
				targets = #targets,
			}
			local names = vim.tbl_keys(get_adapters())
			table.sort(names)
			local function next_adapter(index)
				if job.done then
					return
				end
				local name = names[index]
				if name then
					local adapter, options = adapters[name], ctx.config.sync.languages[name]
					if not options or not options.enabled then
						next_adapter(index + 1)
						return
					end
					local ok, detected = pcall(adapter.detect, ctx)
					if ok and not detected then
						next_adapter(index + 1)
						return
					end
					if not ok then
						entry.adapters[name] = { status = "failed", message = tostring(detected) }
						next_adapter(index + 1)
						return
					end
					local completed = false
					local function done(result)
						if completed or job.done then
							return
						end
						completed = true
						entry.adapters[name] = result
						next_adapter(index + 1)
					end
					local success, message = pcall(adapter.discover, ctx, done)
					if not success then
						done({ status = "failed", message = tostring(message) })
					end
					return
				end
				cache.snapshot(ctx, function(after, snapshot_error)
					if not after or not vim.deep_equal(before, after) then
						vim.notify(
							"bzl.nvim: build inputs changed during sync; run :Bzl sync again. "
								.. (snapshot_error or ""),
							vim.log.levels.WARN
						)
						job.finish({ status = "stale" })
						return
					end
					entry.inputs = after
					entry.applied = apply(ctx, entry)
					states[ctx.root] = entry
					local complete, messages = true, {}
					local stored = vim.deepcopy(entry)
					local old = available[ctx.root] or cache.load(ctx)
					if
						old
						and (old.key ~= ctx.key or not vim.deep_equal(old.inputs, after) or not cache.valid_files(old))
					then
						old = nil
					end
					for adapter_name, result in pairs(entry.adapters) do
						if result.status == "skipped" then
							stored.adapters[adapter_name] = nil
						elseif result.status ~= "ready" then
							complete = false
							stored.adapters[adapter_name] = old and old.adapters[adapter_name] or nil
						end
						messages[#messages + 1] = adapter_name
							.. ": "
							.. result.status
							.. (result.message and " (" .. result.message .. ")" or "")
					end
					for adapter_name, result in pairs(entry.applied) do
						for _, note in ipairs(result.notes) do
							complete = false
							messages[#messages + 1] = adapter_name .. ": " .. note
						end
					end
					local saved, save_error = cache.save(ctx, stored)
					available[ctx.root] = stored
					if not saved then
						messages[#messages + 1] = "cache: " .. save_error
					end
					table.sort(messages)
					vim.notify(
						("bzl.nvim: synced %d targets in %d ms%s"):format(
							#targets,
							(vim.uv.hrtime() - started) / 1e6,
							#messages > 0 and "\n" .. table.concat(messages, "\n") or ""
						),
						complete and vim.log.levels.INFO or vim.log.levels.WARN
					)
					job.finish({ status = complete and "ready" or "partial", entry = entry })
				end)
			end
			next_adapter(1)
		end)
	end, { refresh = true, scope = ctx.scope, config = ctx.config })
	return job
end

---Revalidate cached metadata on attachment; never start an implicit build.
function M.attach(client, root)
	local active = root and states[root]
	local ctx = M.context(root, active and active.scope)
	if not ctx or running[ctx.root] then
		return
	end
	local entry = available[ctx.root] or cache.load_latest(ctx)
	if entry then
		ctx = M.context(root, entry.scope)
	end
	if not entry or entry.key ~= ctx.key or not cache.valid_files(entry) then
		return
	end
	local generation = generations[ctx.root]
	local job = { handles = {}, cleanups = {}, done = false }
	bind(ctx, job)
	cache.snapshot(ctx, function(inputs)
		job.done = true
		if
			generations[ctx.root] == generation
			and not running[ctx.root]
			and inputs
			and vim.deep_equal(inputs, entry.inputs)
			and util.owns(client, ctx.root)
		then
			entry.applied = apply(ctx, entry, client)
			states[ctx.root], available[ctx.root] = entry, entry
		else
			vim.notify("bzl.nvim: cached language metadata is stale; run :Bzl sync", vim.log.levels.INFO)
		end
	end)
end

return M

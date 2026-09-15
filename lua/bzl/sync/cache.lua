local M = { version = 2 }
local util = require("bzl.languages.util")

function M.directory()
	return vim.fn.stdpath("cache") .. "/bzl/sync"
end

function M.key(ctx)
	return vim.fn.sha256(vim.inspect({
		M.version,
		ctx.root,
		vim.deepcopy(ctx.scope),
		ctx.config.bazel_cmd,
		ctx.config.startup_args,
		ctx.config.command_args,
		ctx.config.sync,
	}))
end

function M.path(ctx)
	return M.directory() .. "/" .. ctx.key .. ".json"
end

function M.stamp(path)
	-- Extensions can regenerate identical .bzl files when a repository is injected.
	local contents = util.read(path)
	return contents and vim.fn.sha256(contents) or false
end

---Query the input set again to detect newly added/deleted BUILD files too.
function M.snapshot(ctx, callback)
	ctx.run({ "info", "output_base" }, function(info)
		if info.code ~= 0 then
			callback(nil, info.stderr)
			return
		end
		local output_base = vim.trim(info.stdout)
		ctx.run({
			"query",
			"buildfiles(" .. require("bzl.targets").expression(ctx.scope) .. ")",
			"--output=label",
			"--consistent_labels",
		}, function(result)
			if result.code ~= 0 then
				callback(nil, result.stderr)
				return
			end
			local inputs = {}
			for line in result.stdout:gmatch("[^\r\n]+") do
				local repo, package, name = line:match("^@@([^/]*)//(.-):(.+)$")
				if not repo then
					package, name = line:match("^//(.-):(.+)$")
					repo = ""
				end
				if not name then
					callback(nil, "Unrecognized build input label: " .. line)
					return
				end
				local base = repo == "" and ctx.root or output_base .. "/external/" .. repo
				local path = vim.fs.normalize(base .. "/" .. package .. "/" .. name)
				inputs[path] = M.stamp(path)
			end
			for _, name in ipairs({
				"MODULE.bazel",
				"MODULE.bazel.lock",
				"WORKSPACE",
				"WORKSPACE.bazel",
				".bazelrc",
				".bazelversion",
				"pyproject.toml",
				"pyrightconfig.json",
			}) do
				local path = ctx.root .. "/" .. name
				inputs[path] = M.stamp(path)
			end
			-- Repository-extension inputs such as requirements_lock and go_mod.
			for label in (util.read(ctx.root .. "/MODULE.bazel") or ""):gmatch("[\"'](//[^\"'\n]+)[\"']") do
				local package, name = label:match("^//(.-):(.+)$")
				if name then
					local path = vim.fs.normalize(ctx.root .. "/" .. package .. "/" .. name)
					inputs[path] = M.stamp(path)
				end
			end
			for _, input in ipairs(ctx.config.sync.inputs) do
				local path = util.absolute(ctx.root, input)
				inputs[path] = M.stamp(path)
			end
			local user_rc = vim.fn.expand("~/.bazelrc")
			inputs[user_rc] = M.stamp(user_rc)
			local plugin =
				vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)))))
			local aspect = plugin .. "/bazel/python.bzl"
			inputs[aspect] = M.stamp(aspect)
			callback(inputs)
		end)
	end)
end

function M.load(ctx)
	if not ctx.config.sync.cache then
		return nil
	end
	local value = util.json(M.path(ctx))
	if
		value
		and value.version == M.version
		and value.key == ctx.key
		and value.root == ctx.root
		and vim.deep_equal(value.scope, ctx.scope)
		and type(value.inputs) == "table"
		and type(value.adapters) == "table"
		and M.valid_files(value)
	then
		return value
	end
end

local function latest_path(ctx)
	local default = vim.deepcopy(ctx)
	default.scope = default.config.sync.targets
	return M.directory() .. "/" .. M.key(default) .. "-latest.json"
end

function M.load_latest(ctx)
	if not ctx.config.sync.cache then
		return nil
	end
	local latest = util.json(latest_path(ctx))
	if latest and type(latest.scope) == "table" and vim.islist(latest.scope) then
		for _, target in ipairs(latest.scope) do
			if type(target) ~= "string" then
				return nil
			end
		end
		local selected = vim.deepcopy(ctx)
		selected.scope = latest.scope
		selected.key = M.key(selected)
		return M.load(selected)
	end
	return M.load(ctx)
end

local function write(path, value)
	vim.fn.mkdir(M.directory(), "p", 448)
	local tmp = path .. "." .. tostring(vim.uv.hrtime()) .. ".tmp"
	local ok, err = pcall(function()
		assert(vim.fn.writefile({ vim.json.encode(value) }, tmp) == 0)
		assert(vim.uv.fs_chmod(tmp, 384))
		assert(vim.uv.fs_rename(tmp, path))
	end)
	if not ok then
		pcall(vim.uv.fs_unlink, tmp)
		return false, tostring(err)
	end
	return true
end

function M.save(ctx, value)
	if not ctx.config.sync.cache then
		return true
	end
	local ok, err = write(M.path(ctx), value)
	if not ok then
		return false, err
	end
	return write(latest_path(ctx), { scope = ctx.scope })
end

function M.valid_files(entry)
	for _, result in pairs(entry.adapters or {}) do
		if type(result) ~= "table" then
			return false
		end
		local metadata = result.metadata or {}
		if
			type(metadata) ~= "table"
			or type(metadata.files or {}) ~= "table"
			or type(metadata.fingerprints or {}) ~= "table"
		then
			return false
		end
		for _, path in ipairs(metadata.files or {}) do
			if type(path) ~= "string" then
				return false
			end
			if not vim.uv.fs_stat(path) then
				return false
			end
		end
		for path, stamp in pairs(metadata.fingerprints or {}) do
			if type(path) ~= "string" or M.stamp(path) ~= stamp then
				return false
			end
		end
	end
	return true
end

return M

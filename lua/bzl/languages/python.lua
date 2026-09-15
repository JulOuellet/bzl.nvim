local util = require("bzl.languages.util")
local M = { clients = { pyright = true, basedpyright = true } }
local plugin = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)))))

function M.detect(ctx)
	return util.has_kind(ctx, "^py_")
		or (util.read(ctx.root .. "/MODULE.bazel") or ""):find("name%s*=%s*[\"']rules_python[\"']") ~= nil
end

---Map runfiles import roots using actual source artifacts, including bazel-out.
function M.paths(records, root, execution_root)
	local paths, files, missing = { root }, {}, {}
	for _, record in ipairs(records) do
		assert(
			record.version == 1 and type(record.imports) == "table" and type(record.sources) == "table",
			"unsupported Python metadata schema"
		)
		if record.venv then
			return nil, "This target uses rules_python venv_symlinks; its layout is not supported by this adapter yet"
		end
		local sources = {}
		for _, source in ipairs(record.sources) do
			local external = source.short_path:sub(1, 3) == "../"
			local runfile = external and source.short_path:sub(4)
				or (record.workspace or "_main") .. "/" .. source.short_path
			local path = util.absolute(source.source and not external and root or execution_root, source.path)
			sources[#sources + 1] = { runfile = runfile, path = path }
			if vim.uv.fs_stat(path) then
				files[#files + 1] = path
			else
				missing[#missing + 1] = path
			end
		end
		for _, import in ipairs(record.imports) do
			for _, source in ipairs(sources) do
				if source.runfile:sub(1, #import + 1) == import .. "/" then
					local suffix = source.runfile:sub(#import + 2)
					if source.path:sub(-#suffix) == suffix then
						local dir = source.path:sub(1, -#suffix - 2)
						if vim.uv.fs_stat(dir) then
							paths[#paths + 1] = dir
						end
					end
				end
			end
		end
	end
	return { paths = util.unique(paths), files = util.unique(files) },
		#missing > 0
				and ("Generated/dependency files are missing; enable python.materialize and sync again (" .. missing[1] .. ")")
			or nil
end

local function scan(ctx, done)
	ctx.run({ "info", "output_base" }, function(info)
		if info.code ~= 0 then
			done(util.failed(info))
			return
		end
		local paths = require("bzl.python").site_packages(vim.trim(info.stdout) .. "/external")
		ctx.run({
			"query",
			'kind("py_.*", ' .. require("bzl.targets").expression(ctx.scope) .. ")",
			"--output=streamed_jsonproto",
		}, function(result)
			if result.code ~= 0 then
				done(util.failed(result))
				return
			end
			table.insert(paths, 1, ctx.root)
			vim.list_extend(paths, require("bzl.python").parse_import_roots(result.stdout, ctx.root))
			paths = util.unique(paths)
			done(
				util.result(
					{ paths = paths, files = paths },
					"compatibility scan: materialized dependencies only; not target-accurate"
				)
			)
		end)
	end)
end

function M.discover(ctx, done)
	local options = ctx.config.sync.languages.python
	if options.mode == "scan" then
		scan(ctx, done)
		return
	end
	local events = vim.fn.tempname()
	local args = { "build" }
	vim.list_extend(args, ctx.scope)
	vim.list_extend(args, {
		"--inject_repository=bzl_nvim=" .. plugin .. "/bazel",
		"--aspects=@bzl_nvim//:python.bzl%python",
		"--output_groups=bzl_python" .. (options.materialize and ",bzl_python_sources" or ""),
		"--build_event_json_file=" .. events,
		"--remote_download_outputs=all",
	})
	-- BEP contains process environment information. It is temporary and never cached.
	ctx.cleanup(function()
		pcall(vim.uv.fs_unlink, events)
	end)
	assert(vim.fn.writefile({}, events) == 0, "Cannot create private build-event file")
	assert(vim.uv.fs_chmod(events, 384))
	ctx.run(args, function(result)
		if result.code ~= 0 then
			pcall(vim.uv.fs_unlink, events)
			done(util.failed(result))
			return
		end
		local records, seen = {}, {}
		local file = io.open(events, "r")
		if not file then
			done({ status = "failed", message = "Bazel did not produce a local build-event file" })
			return
		end
		local ok, err = pcall(function()
			for line in file:lines() do
				local event = vim.json.decode(line)
				for _, artifact in ipairs((event.namedSetOfFiles or {}).files or {}) do
					if
						artifact.uri
						and artifact.uri:match("^file:")
						and artifact.name
						and artifact.name:match("%.bzl%-python%.json$")
					then
						local path = vim.uri_to_fname(artifact.uri)
						if not seen[path] then
							seen[path] = true
							records[#records + 1] = assert(util.json(path), "Missing Python metadata: " .. path)
						end
					end
				end
			end
		end)
		file:close()
		pcall(vim.uv.fs_unlink, events)
		if not ok then
			done({ status = "failed", message = tostring(err) })
			return
		end
		if #records == 0 then
			done({
				status = util.has_kind(ctx, "^py_") and "unsupported" or "skipped",
				message = "No supported PyInfo targets in this scope",
			})
			return
		end
		ctx.run({ "info", "execution_root" }, function(info)
			if info.code ~= 0 then
				done(util.failed(info))
				return
			end
			local success, metadata, warning = pcall(M.paths, records, ctx.root, vim.trim(info.stdout))
			if not success then
				done({ status = "failed", message = tostring(metadata) })
				return
			end
			if warning then
				done({ status = metadata and "partial" or "unsupported", message = warning })
				return
			end
			done(util.result(metadata, ("%d paths from %d configured targets"):format(#metadata.paths, #records)))
		end)
	end)
end

function M.apply(ctx, metadata, client)
	local config = util.read(ctx.root .. "/pyrightconfig.json") or ""
	local toml = util.read(ctx.root .. "/pyproject.toml") or ""
	if
		config:find('"executionEnvironments"%s*:')
		or config:find('"extraPaths"%s*:')
		or toml:find("executionEnvironments%s*=")
		or toml:find("extraPaths%s*=")
	then
		return false,
			"Project configuration may override extraPaths; merge Bazel paths in that configuration or remove the override"
	end
	local namespace = client.name == "basedpyright" and "basedpyright" or "python"
	client.settings = vim.deepcopy(client.settings or {})
	client.settings[namespace] = client.settings[namespace] or {}
	local settings = client.settings[namespace]
	settings.analysis = settings.analysis or {}
	settings.analysis.extraPaths = util.merge_paths(client, "python", settings.analysis.extraPaths, metadata.paths)
	local notified = client:notify("workspace/didChangeConfiguration", { settings = client.settings })
	return notified ~= false
end

return M

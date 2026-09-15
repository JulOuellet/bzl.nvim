local util = require("bzl.languages.util")
local M = { clients = { rust_analyzer = true } }

function M.detect(ctx)
	return util.has_kind(ctx, "^rust_")
end

function M.discover(ctx, done)
	local options = ctx.config.sync.languages.rust
	local function read()
		local path = util.absolute(ctx.root, options.project)
		local project = util.json(path)
		if not project or type(project.crates) ~= "table" or #project.crates == 0 then
			done({
				status = "unsupported",
				message = "Configure rust.refresh with your rules_rust exporter; missing/empty " .. path,
			})
			return
		end
		local files = { path }
		for _, crate in ipairs(project.crates) do
			if type(crate.root_module) ~= "string" then
				done({ status = "failed", message = "Rust project has no root_module" })
				return
			end
			files[#files + 1] = util.absolute(vim.fs.dirname(path), crate.root_module)
		end
		for _, file in ipairs(files) do
			if not vim.uv.fs_stat(file) then
				done({ status = "partial", message = "Missing Rust source: " .. file })
				return
			end
		end
		done(
			util.result(
				{ project = path, files = files, fingerprints = { [path] = require("bzl.sync.cache").stamp(path) } },
				"crate graph loaded"
			)
		)
	end
	if #options.refresh == 0 then
		read()
		return
	end
	ctx.run(options.refresh, function(result)
		if result.code == 0 then
			read()
		else
			done(util.failed(result))
		end
	end)
end

function M.apply(_, metadata, client)
	client.settings = vim.deepcopy(client.settings or {})
	client.settings["rust-analyzer"] = client.settings["rust-analyzer"] or {}
	local settings = client.settings["rust-analyzer"]
	settings.linkedProjects = util.merge_paths(client, "rust", settings.linkedProjects, { metadata.project })
	return client:notify("workspace/didChangeConfiguration", { settings = client.settings }) ~= false
end

return M

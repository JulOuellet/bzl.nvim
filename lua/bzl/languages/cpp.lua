local util = require("bzl.languages.util")
local M = { clients = { clangd = true } }

function M.detect(ctx)
	return util.has_kind(ctx, "^cc_")
end

function M.discover(ctx, done)
	local options = ctx.config.sync.languages.cpp
	local function read()
		local path = util.absolute(ctx.root, options.database)
		local database = util.json(path)
		if not database or not vim.islist(database) then
			done({
				status = "unsupported",
				message = "Configure cpp.refresh with your compilation database exporter; missing/invalid " .. path,
			})
			return
		end
		local commands = {}
		for _, entry in ipairs(database) do
			if
				type(entry.directory) ~= "string"
				or type(entry.file) ~= "string"
				or type(entry.arguments) ~= "table"
				or not vim.islist(entry.arguments)
				or #entry.arguments == 0
			then
				done({
					status = "unsupported",
					message = "Compilation database must use arguments arrays (for example Hedron's exporter)",
				})
				return
			end
			for _, arg in ipairs(entry.arguments) do
				if type(arg) ~= "string" then
					done({ status = "failed", message = "Compilation arguments must be strings" })
					return
				end
			end
			local dir = util.absolute(ctx.root, entry.directory)
			commands[util.absolute(dir, entry.file)] = { workingDirectory = dir, compilationCommand = entry.arguments }
		end
		if next(commands) == nil then
			done({ status = "partial", message = "Compilation database is empty" })
			return
		end
		done(util.result({
			commands = commands,
			files = { path },
			fingerprints = { [path] = require("bzl.sync.cache").stamp(path) },
		}, "compilation database loaded"))
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
	local current = (client.settings or {}).compilationDatabaseChanges or {}
	local previous = client._bzl_cpp_commands or {}
	-- clangd's extension updates entries but has no per-file deletion operation.
	for path in pairs(previous) do
		if not metadata.commands[path] then
			return false, "Compilation scope removed files; restart clangd to discard old commands"
		end
	end
	for path, command in pairs(metadata.commands) do
		if
			current[path]
			and not vim.deep_equal(current[path], previous[path])
			and not vim.deep_equal(current[path], command)
		then
			return false, "Preserved user compilation command for " .. path
		end
	end
	client.settings = vim.deepcopy(client.settings or {})
	client.settings.compilationDatabaseChanges =
		vim.tbl_extend("force", client.settings.compilationDatabaseChanges or {}, metadata.commands)
	client._bzl_cpp_commands = vim.deepcopy(metadata.commands)
	return client:notify("workspace/didChangeConfiguration", { settings = client.settings }) ~= false
end

return M

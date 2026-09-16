local M = {}

local namespaces = { pyright = "python", basedpyright = "basedpyright" }
local managed = setmetatable({}, { __mode = "k" })

function M.belongs(client, root)
	return namespaces[client.name] ~= nil and require("bzl.lsp").belongs(client, root)
end

---Replace only our previous contribution, retaining user paths and edits.
function M.apply(client, root, model)
	if not M.belongs(client, root) then
		return false
	end
	local namespace = namespaces[client.name]
	local settings = vim.deepcopy(client.settings or {})
	settings[namespace] = settings[namespace] or {}
	settings[namespace].analysis = settings[namespace].analysis or {}
	local analysis = settings[namespace].analysis
	local previous = managed[client] or { paths = {}, user = {} }
	local user, paths = {}, {}
	for _, path in ipairs(analysis.extraPaths or {}) do
		if not previous.paths[path] or previous.user[path] then
			user[path] = true
			paths[#paths + 1] = path
		end
	end
	local contributed = {}
	for _, path in ipairs(model.paths) do
		contributed[path] = true
		if not vim.tbl_contains(paths, path) then
			paths[#paths + 1] = path
		end
	end
	analysis.extraPaths = paths

	settings.python = settings.python or {}
	local interpreter = settings.python.pythonPath
	local next_managed = { paths = contributed, user = user }
	if interpreter == nil or interpreter == previous.interpreter then
		settings.python.pythonPath = model.interpreter
		next_managed.interpreter = model.interpreter
	end
	managed[client] = next_managed
	if not vim.deep_equal(settings, client.settings) then
		client.settings = settings
		client:notify("workspace/didChangeConfiguration", { settings = settings })
	end
	return true
end

return M

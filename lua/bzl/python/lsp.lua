local M = {}

local namespaces = { pyright = "python", basedpyright = "basedpyright" }
local managed = setmetatable({}, { __mode = "k" })

local function normalize(path)
	return vim.fs.normalize(vim.uv.fs_realpath(path) or path)
end

local function inside(path, root)
	path = normalize(path)
	return path == root or path:sub(1, #root + 1) == root .. "/"
end

---Do not send workspace-wide settings to a client shared with another workspace.
function M.belongs(client, root)
	if not namespaces[client.name] then
		return false
	end
	root = normalize(root)
	if client.root_dir then
		if not inside(client.root_dir, root) then
			return false
		end
		local workspace = require("bzl.cli").workspace_root(client.root_dir)
		if workspace and normalize(workspace) ~= root then
			return false
		end
	end
	local known = client.root_dir ~= nil
	for _, folder in ipairs(client.workspace_folders or {}) do
		if not inside(vim.uri_to_fname(folder.uri), root) then
			return false
		end
		known = true
	end
	-- A rooted server may also attach to generated files and external libraries.
	-- Its declared workspace remains authoritative; buffers identify rootless servers.
	if known then
		return true
	end
	for buf in pairs(client.attached_buffers or {}) do
		if vim.api.nvim_buf_is_valid(buf) then
			local workspace = require("bzl.cli").workspace_root(buf)
			if not workspace or normalize(workspace) ~= root then
				return false
			end
			known = true
		end
	end
	return known
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

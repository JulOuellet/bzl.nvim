local M = {}

---Neovim 0.10 has bound client functions; 0.11+ uses methods.
function M.notify(client, method, params)
	if vim.fn.has("nvim-0.11") == 1 then
		return client:notify(method, params)
	end
	return client.notify(method, params)
end

local function normalize(path)
	return vim.fs.normalize(vim.uv.fs_realpath(path) or path)
end

local function inside(path, root)
	path = normalize(path)
	return path == root or path:sub(1, #root + 1) == root .. "/"
end

---Do not send workspace-wide settings to a client shared with another workspace.
function M.belongs(client, root)
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
		local path = vim.uri_to_fname(folder.uri)
		local workspace = require("bzl.cli").workspace_root(path)
		if not inside(path, root) or (workspace and normalize(workspace) ~= root) then
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

return M

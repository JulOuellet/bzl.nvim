local M = {}

function M.inside(path, root)
	path, root = vim.fs.normalize(path), vim.fs.normalize(root)
	return path == root or path:sub(1, #root + 1) == root .. "/"
end

function M.read(path)
	local file = io.open(path, "r")
	if not file then
		return nil
	end
	local value = file:read("*a")
	file:close()
	return value
end

function M.json(path)
	local ok, value = pcall(vim.json.decode, M.read(path) or "")
	return ok and type(value) == "table" and value or nil
end

function M.absolute(root, path)
	return vim.fs.normalize(path:sub(1, 1) == "/" and path or root .. "/" .. path)
end

function M.unique(values)
	local seen, result = {}, {}
	for _, value in ipairs(values) do
		if not seen[value] then
			seen[value] = true
			result[#result + 1] = value
		end
	end
	return result
end

---A shared/rootless client must not acquire another workspace's settings.
function M.owns(client, root)
	local found = false
	local function check(path)
		if not path or path == "" then
			return true
		end
		if not M.inside(path, root) then
			return false
		end
		local workspace = vim.fs.root(path, { "MODULE.bazel", "WORKSPACE", "WORKSPACE.bazel" })
		if workspace and vim.fs.normalize(workspace) ~= root then
			return false
		end
		found = true
		return true
	end
	if not check(client.root_dir or (client.config or {}).root_dir) then
		return false
	end
	for _, folder in ipairs(client.workspace_folders or {}) do
		if not check(vim.uri_to_fname(folder.uri)) then
			return false
		end
	end
	for buf, attached in pairs(client.attached_buffers or {}) do
		if attached and vim.api.nvim_buf_is_valid(buf) then
			if not check(vim.api.nvim_buf_get_name(buf)) then
				return false
			end
		end
	end
	return found
end

---Replace only our previous contribution, retaining user edits and path order.
function M.merge_paths(client, key, current, paths)
	client._bzl_paths = client._bzl_paths or {}
	local previous = client._bzl_paths[key] or { added = {} }
	local users = {}
	for _, path in ipairs(current or {}) do
		if not previous.added[path] then
			users[#users + 1] = path
		end
	end
	local present, added = {}, {}
	for _, path in ipairs(users) do
		present[path] = true
	end
	for _, path in ipairs(paths) do
		if not present[path] then
			users[#users + 1] = path
			present[path] = true
			added[path] = true
		end
	end
	client._bzl_paths[key] = { added = added }
	return users
end

function M.has_kind(ctx, pattern)
	for _, target in ipairs(ctx.targets or {}) do
		if target.kind:match(pattern) then
			return true
		end
	end
	return false
end

function M.failed(result)
	return {
		status = result.status == "cancelled" and "cancelled" or "failed",
		message = (result.stderr or "Bazel failed"):sub(-4000),
	}
end

function M.result(metadata, message)
	return { status = "ready", metadata = metadata, message = message }
end

return M

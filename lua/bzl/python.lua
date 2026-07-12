local M = {}

---Client names that understand `python.analysis.extraPaths`.
local PYTHON_CLIENTS = { pyright = true, basedpyright = true }

---Absolute paths of every `site-packages` directory one level under
---the given external repository root. Detects by content rather than
---repository naming, which varies across rules_python versions.
---@param external_dir string e.g. "<output_base>/external"
---@return string[] sorted site-packages paths
function M.site_packages(external_dir)
	local paths = {}
	local handle = vim.uv.fs_scandir(external_dir)
	if not handle then
		return paths
	end
	while true do
		local name = vim.uv.fs_scandir_next(handle)
		if not name then
			break
		end
		local candidate = external_dir .. "/" .. name .. "/site-packages"
		local stat = vim.uv.fs_stat(candidate)
		if stat and stat.type == "directory" then
			paths[#paths + 1] = candidate
		end
	end
	table.sort(paths)
	return paths
end

---Push extraPaths to python language servers via
---workspace/didChangeConfiguration; earlier paths are replaced, other
---settings are kept. The client list is injectable for testing and
---defaults to the attached pyright/basedpyright clients.
---@param paths string[]
---@param clients vim.lsp.Client[]|nil
---@return integer clients number of clients notified
function M.push_extra_paths(paths, clients)
	clients = clients
		or vim.tbl_filter(function(client)
			return PYTHON_CLIENTS[client.name] ~= nil
		end, vim.lsp.get_clients())

	for _, client in ipairs(clients) do
		client.settings = vim.tbl_deep_extend("force", client.settings or {}, {
			python = { analysis = { extraPaths = paths } },
		})
		client:notify("workspace/didChangeConfiguration", { settings = client.settings })
	end
	return #clients
end

---Discover site-packages under the workspace's bazel external root and
---push them to the attached python language servers.
---`on_done` is called exactly once; nil means the discovery failed.
---@param on_done fun(result: { paths: integer, clients: integer }|nil)
function M.sync(on_done)
	local cli = require("bzl.cli")
	local root = cli.workspace_root()

	local started = cli.run({ "info", "output_base" }, function(result)
		if result.code ~= 0 then
			vim.notify("bzl.nvim: bazel info failed:\n" .. (result.stderr or ""), vim.log.levels.ERROR)
			on_done(nil)
			return
		end
		local output_base = vim.trim(result.stdout or "")
		local paths = M.site_packages(output_base .. "/external")
		if root then
			table.insert(paths, 1, root)
		end
		local clients = M.push_extra_paths(paths)
		on_done({ paths = #paths, clients = clients })
	end)
	if not started then
		on_done(nil)
	end
end

return M

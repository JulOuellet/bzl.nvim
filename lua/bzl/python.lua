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

---Whether a path is the root itself or lies inside it.
local function inside(path, root)
	return path == root or path:sub(1, #root + 1) == root .. "/"
end

---Push extraPaths to python language servers via
---workspace/didChangeConfiguration; earlier paths are replaced, other
---settings are kept. Only clients rooted inside the given workspace are
---updated, so syncing one workspace never rewrites another's paths.
---The client list is injectable for testing and defaults to the
---attached pyright/basedpyright clients.
---@param paths string[]
---@param root string|nil workspace root; nil disables the root filter
---@param clients vim.lsp.Client[]|nil
---@return integer clients number of clients notified
function M.push_extra_paths(paths, root, clients)
	clients = clients
		or vim.tbl_filter(function(client)
			return PYTHON_CLIENTS[client.name] ~= nil
		end, vim.lsp.get_clients())

	local updated = 0
	for _, client in ipairs(clients) do
		-- clients without a root_dir (single-file mode) are included:
		-- their workspace cannot be proven foreign
		if not root or not client.root_dir or inside(client.root_dir, root) then
			client.settings = vim.tbl_deep_extend("force", client.settings or {}, {
				python = { analysis = { extraPaths = paths } },
			})
			client:notify("workspace/didChangeConfiguration", { settings = client.settings })
			updated = updated + 1
		end
	end
	return updated
end

---Collapse "." and ".." segments of an absolute path. Pure function.
---@param path string
---@return string
local function collapse(path)
	local parts = {}
	for part in path:gmatch("[^/]+") do
		if part == ".." then
			table.remove(parts)
		elseif part ~= "." then
			parts[#parts + 1] = part
		end
	end
	return "/" .. table.concat(parts, "/")
end

---Derive first-party import roots from the `imports` attributes of py
---rules in `bazel query --output=streamed_jsonproto` output: each entry
---adds a sys.path root relative to the rule's package. Pure function.
---@param output string one JSON object per line
---@param root string workspace root (absolute path)
---@return string[] sorted absolute roots, deduplicated
function M.parse_import_roots(output, root)
	local roots, seen = {}, {}
	for line in output:gmatch("[^\r\n]+") do
		local ok, target = pcall(vim.json.decode, line)
		local rule = ok and type(target) == "table" and target.type == "RULE" and target.rule or nil
		if rule then
			local pkg = (rule.name or ""):match("^//([^:]*):")
			for _, attr in ipairs(rule.attribute or {}) do
				if attr.name == "imports" and attr.explicitlySpecified then
					for _, entry in ipairs(attr.stringListValue or {}) do
						local dir = collapse(root .. "/" .. (pkg or "") .. "/" .. entry)
						if not seen[dir] then
							seen[dir] = true
							roots[#roots + 1] = dir
						end
					end
				end
			end
		end
	end
	table.sort(roots)
	return roots
end

---Query the workspace for first-party import roots.
---@param on_done fun(roots: string[]|nil)
local function import_roots(root, on_done)
	require("bzl.cli").run({ "query", 'kind("py_.*", //...)', "--output=streamed_jsonproto" }, function(result)
		if result.code ~= 0 then
			vim.notify("bzl.nvim: bazel query for imports failed:\n" .. (result.stderr or ""), vim.log.levels.ERROR)
			on_done(nil)
			return
		end
		on_done(M.parse_import_roots(result.stdout or "", root))
	end)
end

---Discover site-packages under the workspace's bazel external root plus
---first-party import roots, and push them to the attached python
---language servers. `on_done` is called exactly once; nil means the
---discovery failed.
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
		if not root then
			local clients = M.push_extra_paths(paths, nil)
			on_done({ paths = #paths, clients = clients })
			return
		end
		table.insert(paths, 1, root)
		import_roots(root, function(roots)
			-- push what we have even if the roots query failed
			for _, dir in ipairs(roots or {}) do
				if dir ~= root then
					paths[#paths + 1] = dir
				end
			end
			local clients = M.push_extra_paths(paths, root)
			on_done({ paths = #paths, clients = clients })
		end)
	end)
	if not started then
		on_done(nil)
	end
end

return M

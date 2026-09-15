local M = {}

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

return M

local M = {}

---Reject partial or malformed metadata instead of replacing a working model.
function M.parse(output)
	local records = {}
	for line in output:gmatch("[^\r\n]+") do
		if vim.trim(line) ~= "" then
			local ok, record = pcall(vim.json.decode, line)
			if ok and type(record) == "table" and type(record.error) == "string" then
				return nil, record.error
			end
			if not ok or type(record) ~= "table" or type(record.label) ~= "string" then
				return nil, "invalid Python metadata from bazel cquery"
			end
			for _, field in ipairs({ "imports", "roots", "generated" }) do
				if type(record[field]) ~= "table" or not vim.islist(record[field]) then
					return nil, "missing Python metadata field: " .. field
				end
			end
			for _, path in ipairs(vim.list_extend(vim.deepcopy(record.imports), record.generated)) do
				if type(path) ~= "string" then
					return nil, "invalid path in Python metadata"
				end
			end
			for _, root in ipairs(record.roots) do
				if type(root) ~= "table" or type(root.repo) ~= "string" or type(root.path) ~= "string" then
					return nil, "invalid source root in Python metadata"
				end
			end
			for _, field in ipairs({ "interpreter", "version" }) do
				if record[field] == vim.NIL then
					record[field] = nil
				elseif record[field] ~= nil and type(record[field]) ~= "string" then
					return nil, "invalid Python metadata field: " .. field
				end
			end
			records[#records + 1] = record
		end
	end
	table.sort(records, function(a, b)
		return a.label < b.label
	end)
	return records
end

local function absolute(path, execution_root)
	return vim.fs.normalize(path:sub(1, 1) == "/" and path or (execution_root .. "/" .. path))
end

---Map PyInfo's runfiles-relative imports to source and generated roots.
---All paths come from the selected configured targets, never a cache scan.
function M.resolve(records, root, execution_root)
	local paths, seen = {}, {}
	local function add(path)
		path = vim.fs.normalize(path)
		local stat = vim.uv.fs_stat(path)
		if not seen[path] and stat and stat.type == "directory" then
			seen[path] = true
			paths[#paths + 1] = path
		end
	end
	local interpreters, versions = {}, {}
	for _, record in ipairs(records) do
		for _, file in ipairs(record.generated) do
			if not vim.uv.fs_stat(absolute(file, execution_root)) then
				return nil, "generated Python source was not built: " .. file
			end
		end
		local roots = { [""] = { root } }
		for _, source in ipairs(record.roots) do
			local base = source.path == "" and root or absolute(source.path, execution_root)
			roots[source.repo] = roots[source.repo] or {}
			if not vim.tbl_contains(roots[source.repo], base) then
				table.insert(roots[source.repo], base)
			end
		end
		for _, base in ipairs(roots[""]) do
			add(base)
		end
		for _, import in ipairs(record.imports) do
			local repo, relative = import:match("^([^/]+)/?(.*)$")
			if repo == vim.fs.basename(execution_root) then
				repo = ""
			end
			if not roots[repo] then
				return nil, "cannot resolve Python import root: " .. import
			end
			for _, base in ipairs(roots[repo]) do
				add(base .. "/" .. relative)
			end
		end
		if record.interpreter then
			interpreters[absolute(record.interpreter, execution_root)] = true
		end
		if record.version then
			versions[record.version] = true
		end
	end
	if vim.tbl_count(interpreters) > 1 or vim.tbl_count(versions) > 1 then
		return nil, "selected targets use different Python runtimes; narrow python.targets"
	end
	return { paths = paths, interpreter = next(interpreters), version = next(versions), targets = #records }
end

return M

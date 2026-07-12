local T = MiniTest.new_set()

local python = require("bzl.python")

T["site_packages"] = MiniTest.new_set()

T["site_packages"]["finds site-packages by content, not by name"] = function()
	local tmp = vim.fn.tempname()
	vim.fn.mkdir(tmp .. "/rules_python++pip+pypi_312_pyspark/site-packages", "p")
	vim.fn.mkdir(tmp .. "/some_other_naming_scheme_numpy/site-packages", "p")
	vim.fn.mkdir(tmp .. "/rules_shell+", "p") -- no site-packages: ignored
	MiniTest.expect.equality(python.site_packages(tmp), {
		tmp .. "/rules_python++pip+pypi_312_pyspark/site-packages",
		tmp .. "/some_other_naming_scheme_numpy/site-packages",
	})
	vim.fn.delete(tmp, "rf")
end

T["site_packages"]["returns an empty list for a missing directory"] = function()
	MiniTest.expect.equality(python.site_packages("/definitely/not/here"), {})
end

T["parse_import_roots"] = MiniTest.new_set()

---@param name string
---@param imports string[]
---@param explicit boolean|nil
local function rule_line(name, imports, explicit)
	return vim.json.encode({
		type = "RULE",
		rule = {
			name = name,
			attribute = {
				{ name = "imports", explicitlySpecified = explicit ~= false, stringListValue = imports },
			},
		},
	})
end

T["parse_import_roots"]["derives roots relative to the rule's package"] = function()
	local output = table.concat({
		rule_line("//common/libs/python:enums", { "enums" }),
		rule_line("//services/api:lib", { "..", "." }),
	}, "\n")
	MiniTest.expect.equality(python.parse_import_roots(output, "/ws"), {
		"/ws/common/libs/python/enums",
		"/ws/services",
		"/ws/services/api",
	})
end

T["parse_import_roots"]["skips defaults, duplicates and noise"] = function()
	local output = table.concat({
		rule_line("//a:x", { "." }, false), -- not explicitly specified
		rule_line("//b:x", { "." }),
		rule_line("//b:y", { "." }), -- duplicate root
		"not json at all",
		vim.json.encode({ type = "SOURCE_FILE" }),
	}, "\n")
	MiniTest.expect.equality(python.parse_import_roots(output, "/ws"), { "/ws/b" })
end

T["push_extra_paths"] = MiniTest.new_set()

T["push_extra_paths"]["updates settings and notifies each client"] = function()
	local notified = {}
	local client = {
		name = "pyright",
		settings = { python = { pythonPath = "/usr/bin/python" } },
		notify = function(_, method, params)
			notified[#notified + 1] = { method = method, params = params }
		end,
	}

	local count = python.push_extra_paths({ "/a", "/b" }, nil, { client })

	MiniTest.expect.equality(count, 1)
	MiniTest.expect.equality(client.settings.python.analysis.extraPaths, { "/a", "/b" })
	-- unrelated settings survive the merge
	MiniTest.expect.equality(client.settings.python.pythonPath, "/usr/bin/python")
	MiniTest.expect.equality(notified[1].method, "workspace/didChangeConfiguration")
	MiniTest.expect.equality(notified[1].params.settings.python.analysis.extraPaths, { "/a", "/b" })
end

T["push_extra_paths"]["notifies zero clients without erroring"] = function()
	MiniTest.expect.equality(python.push_extra_paths({ "/a" }, nil, {}), 0)
end

T["push_extra_paths"]["only updates clients rooted inside the workspace"] = function()
	local function fake_client(root_dir)
		return {
			name = "pyright",
			root_dir = root_dir,
			notified = 0,
			notify = function(self)
				self.notified = self.notified + 1
			end,
		}
	end
	local service = fake_client("/ws/services/api")
	local at_root = fake_client("/ws")
	local other_workspace = fake_client("/elsewhere")
	local prefix_lookalike = fake_client("/ws2/api")
	local rootless = fake_client(nil)

	local count = python.push_extra_paths({ "/p" }, "/ws", {
		service,
		at_root,
		other_workspace,
		prefix_lookalike,
		rootless,
	})

	MiniTest.expect.equality(count, 3)
	MiniTest.expect.equality(service.notified, 1)
	MiniTest.expect.equality(at_root.notified, 1)
	MiniTest.expect.equality(rootless.notified, 1)
	MiniTest.expect.equality(other_workspace.notified, 0)
	MiniTest.expect.equality(prefix_lookalike.notified, 0)
end

return T

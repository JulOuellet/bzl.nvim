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

	local count = python.push_extra_paths({ "/a", "/b" }, { client })

	MiniTest.expect.equality(count, 1)
	MiniTest.expect.equality(client.settings.python.analysis.extraPaths, { "/a", "/b" })
	-- unrelated settings survive the merge
	MiniTest.expect.equality(client.settings.python.pythonPath, "/usr/bin/python")
	MiniTest.expect.equality(notified[1].method, "workspace/didChangeConfiguration")
	MiniTest.expect.equality(notified[1].params.settings.python.analysis.extraPaths, { "/a", "/b" })
end

T["push_extra_paths"]["notifies zero clients without erroring"] = function()
	MiniTest.expect.equality(python.push_extra_paths({ "/a" }, {}), 0)
end

return T

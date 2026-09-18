local M = {}

M.defaults = {
	-- Binary used for all bazel invocations, e.g. "bazelisk" or an absolute path.
	bazel_cmd = "bazel",
	-- Startup flags precede the verb; build flags also apply to sync analysis.
	startup_flags = {},
	build_flags = {},
	python = {
		enabled = true,
		-- Empty means all workspace py_* rules. Explicit labels/patterns also
		-- support custom rules providing PyInfo.
		targets = {},
	},
	go = {
		enabled = true,
		-- nil probes @rules_go and @io_bazel_rules_go. Set a label to override.
	},
	picker = {
		-- Show the BUILD-file preview panel when the picker opens.
		preview = false,
	},
	sync = {
		-- Height of the split that shows sync progress and logs.
		height = 15,
	},
	runner = {
		-- Height of the terminal split that shows run/test output.
		height = 15,
	},
}

local options

---@param opts table|nil
function M.setup(opts)
	opts = vim.deepcopy(opts or {})
	for _, name in ipairs({ "python", "go" }) do
		if type(opts[name]) == "boolean" then
			opts[name] = { enabled = opts[name] }
		end
		assert(opts[name] == nil or type(opts[name]) == "table", name .. " must be a table or boolean")
		assert(
			not opts[name] or opts[name].enabled == nil or type(opts[name].enabled) == "boolean",
			name .. ".enabled must be a boolean"
		)
	end
	options = vim.tbl_deep_extend("force", {}, M.defaults, opts)
end

---Initializes with defaults on first access so calling setup() is optional.
function M.get()
	if not options then
		M.setup()
	end
	return options
end

return M

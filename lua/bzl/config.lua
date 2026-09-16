local M = {}

M.defaults = {
	-- Binary used for all bazel invocations, e.g. "bazelisk" or an absolute path.
	bazel_cmd = "bazel",
	-- Startup flags precede the verb; build flags also apply to sync analysis.
	startup_flags = {},
	build_flags = {},
	python = {
		-- Empty means all workspace py_* rules. Explicit labels/patterns also
		-- support custom rules providing PyInfo.
		targets = {},
	},
	picker = {
		-- Show the BUILD-file preview panel when the picker opens.
		preview = false,
	},
	runner = {
		-- Height of the terminal split that shows run/test output.
		height = 15,
	},
}

local options

---@param opts table|nil
function M.setup(opts)
	options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
end

---Initializes with defaults on first access so calling setup() is optional.
function M.get()
	if not options then
		M.setup()
	end
	return options
end

return M

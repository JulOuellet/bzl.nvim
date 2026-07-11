local M = {}

M.defaults = {
	-- Binary used for all bazel invocations, e.g. "bazelisk" or an absolute path.
	bazel_cmd = "bazel",
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

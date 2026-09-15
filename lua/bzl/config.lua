local M = {}

M.defaults = {
	-- Binary used for all bazel invocations, e.g. "bazelisk" or an absolute path.
	bazel_cmd = "bazel",
	startup_args = {},
	command_args = { query = {}, info = {}, build = {}, run = {}, test = {} },
	sync = {
		targets = { "//..." },
		inputs = {},
		query_timeout = 120000,
		build_timeout = 0,
		cache = true,
		languages = {
			python = { enabled = true, mode = "aspect", materialize = true },
			cpp = { enabled = true, database = "compile_commands.json", refresh = {} },
			go = { enabled = true, driver_target = "@rules_go//go/tools/gopackagesdriver" },
			rust = { enabled = true, project = "rust-project.json", refresh = {} },
		},
	},
	workspaces = {},
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
function M.string_list(value, name)
	assert(type(value) == "table" and vim.islist(value), name .. " must be a list")
	for _, item in ipairs(value) do
		assert(type(item) == "string" and item ~= "", name .. " must contain nonempty strings")
	end
end

local function validate(value)
	assert(type(value.bazel_cmd) == "string" and value.bazel_cmd ~= "", "bazel_cmd must be a nonempty string")
	M.string_list(value.startup_args, "startup_args")
	for name, args in pairs(value.command_args) do
		M.string_list(args, "command_args." .. name)
	end
	M.string_list(value.sync.targets, "sync.targets")
	M.string_list(value.sync.inputs, "sync.inputs")
	assert(#value.sync.targets > 0, "sync.targets must not be empty")
	assert(type(value.sync.cache) == "boolean", "sync.cache must be boolean")
	for _, name in ipairs({ "query_timeout", "build_timeout" }) do
		assert(type(value.sync[name]) == "number" and value.sync[name] >= 0, "sync." .. name .. " must be nonnegative")
	end
	for name, adapter in pairs(value.sync.languages) do
		assert(
			type(adapter) == "table" and type(adapter.enabled) == "boolean",
			"sync.languages." .. name .. ".enabled must be boolean"
		)
		if adapter.refresh then
			M.string_list(adapter.refresh, name .. ".refresh")
		end
	end
	assert(
		value.sync.languages.python.mode == "aspect" or value.sync.languages.python.mode == "scan",
		"python.mode must be aspect or scan"
	)
	assert(type(value.sync.languages.python.materialize) == "boolean", "python.materialize must be boolean")
	for _, field in ipairs({ { "cpp", "database" }, { "rust", "project" }, { "go", "driver_target" } }) do
		local item = value.sync.languages[field[1]][field[2]]
		assert(type(item) == "string" and item ~= "", table.concat(field, ".") .. " must be a nonempty string")
	end
	assert(type(value.picker.preview) == "boolean", "picker.preview must be boolean")
	assert(
		type(value.runner.height) == "number" and value.runner.height > 0 and value.runner.height % 1 == 0,
		"runner.height must be a positive integer"
	)
end

function M.setup(opts)
	assert(opts == nil or type(opts) == "table", "bzl.setup expects a table")
	local next_options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
	validate(next_options)
	for _, override in pairs(next_options.workspaces) do
		validate(vim.tbl_deep_extend("force", vim.deepcopy(next_options), override))
	end
	options = next_options
end

---Initializes with defaults on first access so calling setup() is optional.
function M.get(root)
	if not options then
		M.setup()
	end
	if root and options.workspaces[root] then
		return vim.tbl_deep_extend("force", vim.deepcopy(options), options.workspaces[root])
	end
	return options
end

return M

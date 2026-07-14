local M = {}

---@class bzl.PickerItem
---@field text string what the picker's fuzzy search matches against
---@field label string full target label, e.g. "//lib:greetings"
---@field kind string rule kind, e.g. "sh_test"

---Choose the bazel verb for a rule kind: tests are tested, binaries
---are run, anything else is built. Pure function.
---@param kind string
---@return bzl.Verb
function M.verb_for(kind)
	if kind:match("_test$") then
		return "test"
	elseif kind:match("_binary$") then
		return "run"
	end
	return "build"
end

---Kind predicates for the optional filter argument of the pickers.
M.kind_filters = {
	testable = function(kind)
		return kind:match("_test$") ~= nil
	end,
	-- binaries only: tests have their own filter
	runnable = function(kind)
		return kind:match("_binary$") ~= nil
	end,
}

---Apply a named kind filter. Pure function.
---nil filters nothing; an unknown name returns nil.
---@param targets bzl.Target[]
---@param name string|nil
---@return bzl.Target[]|nil
function M.filter_targets(targets, name)
	if not name then
		return targets
	end
	local predicate = M.kind_filters[name]
	if not predicate then
		return nil
	end
	return vim.tbl_filter(function(target)
		return predicate(target.kind)
	end, targets)
end

---Wildcard label for every target under a directory.
---@param path string workspace-relative dir, "" for the whole workspace
---@return string e.g. "//services/api/..."
function M.subtree_label(path)
	if path == "" then
		return "//..."
	end
	return "//" .. path .. "/..."
end

---Whether a label lives in a directory or its subtree. Pure function.
---@param label string full target label
---@param dir string workspace-relative directory, "" matches everything
---@return boolean
function M.in_project(label, dir)
	if dir == "" then
		return true
	end
	local prefix = "//" .. dir
	local boundary = label:sub(#prefix + 1, #prefix + 1)
	return label:sub(1, #prefix) == prefix and (boundary == ":" or boundary == "/")
end

---Parse picker arguments: kind filters plus the "here" scope keyword.
---Notifies and returns nil on unknown arguments.
---@return { filter: string|nil, here: boolean|nil }|nil
local function parse_args(...)
	local opts = {}
	for _, arg in ipairs({ ... }) do
		if arg == "here" then
			opts.here = true
		elseif M.kind_filters[arg] then
			opts.filter = arg
		else
			local valid = vim.tbl_keys(M.kind_filters)
			table.sort(valid)
			vim.notify(
				("bzl.nvim: unknown argument %q (valid: here, %s)"):format(arg, table.concat(valid, ", ")),
				vim.log.levels.ERROR
			)
			return nil
		end
	end
	return opts
end

---Resolve the current buffer's project scope, notifying on failure.
---@param root string|nil workspace root
---@return string|nil project workspace-relative dir, "" for the root
local function resolve_project(root)
	if not root then
		vim.notify("bzl.nvim: no bazel workspace found", vim.log.levels.ERROR)
		return nil
	end
	local file = vim.api.nvim_buf_get_name(0)
	if file == "" then
		vim.notify("bzl.nvim: the current buffer has no file", vim.log.levels.WARN)
		return nil
	end
	local project = require("bzl.targets").project_of(file, root)
	if not project then
		vim.notify("bzl.nvim: this file is not inside a bazel package", vim.log.levels.WARN)
		return nil
	end
	return project
end

---@param base string
---@param project string|nil
---@param filter string|nil
local function title_for(base, project, filter)
	local parts = {}
	if project and project ~= "" then
		parts[#parts + 1] = "//" .. project
	end
	if filter then
		parts[#parts + 1] = filter
	end
	if #parts == 0 then
		return base
	end
	return base .. " (" .. table.concat(parts, ", ") .. ")"
end

---Narrow a target list by kind filter and project scope.
---@param targets bzl.Target[]|nil
---@param filter string|nil
---@param project string|nil
---@return bzl.Target[]|nil
local function narrow(targets, filter, project)
	targets = targets and M.filter_targets(targets, filter)
	if targets and project then
		targets = vim.tbl_filter(function(target)
			return M.in_project(target.label, project)
		end, targets)
	end
	return targets
end

---Build a target quietly, notifying the outcome.
---@param label string
local function build(label)
	require("bzl.cli").run({ "build", label }, function(result)
		if result.code == 0 then
			vim.notify("bzl.nvim: built " .. label, vim.log.levels.INFO)
		else
			vim.notify(("bzl.nvim: build failed for %s\n%s"):format(label, result.stderr or ""), vim.log.levels.ERROR)
		end
	end)
end

---Close the picker and act on the item: run/test in the runner
---terminal, build quietly in the background.
---@param verb bzl.Verb
local function act(picker, item, verb)
	picker:close()
	if verb == "build" then
		build(item.label)
	else
		require("bzl.runner").execute(verb, item.label)
	end
end

---Location resolver bound to a workspace root, caching results on the
---items themselves. nil = not resolved yet, false = resolved but absent.
---@param root string|nil
local function make_locate(root)
	---@param item bzl.PickerItem
	---@return { file: string, lnum: integer|nil }|nil
	return function(item)
		if not root then
			return nil
		end
		if item._location == nil then
			item._location = require("bzl.targets").location(item.label, root) or false
		end
		return item._location or nil
	end
end

---Preview a target item: its BUILD file, at the target's name line.
local function preview_target(ctx, locate)
	local location = locate(ctx.item)
	if not location then
		ctx.preview:notify("no BUILD file found for " .. ctx.item.label, "warn")
		return
	end
	ctx.item.file = location.file
	ctx.item.pos = location.lnum and { location.lnum, 0 } or nil
	return require("snacks.picker.preview").file(ctx)
end

---Close the picker and jump to the target's definition.
local function goto_target(picker, item, locate)
	picker:close()
	local location = locate(item)
	if not location then
		vim.notify("bzl.nvim: no BUILD file found for " .. item.label, vim.log.levels.WARN)
		return
	end
	vim.cmd.edit(vim.fn.fnameescape(location.file))
	if location.lnum then
		vim.api.nvim_win_set_cursor(0, { location.lnum, 0 })
	end
end

local PICKER_KEYS = {
	["<C-r>"] = { "bzl_run", mode = { "n", "i" } },
	["<C-t>"] = { "bzl_test", mode = { "n", "i" } },
	["<C-b>"] = { "bzl_build", mode = { "n", "i" } },
	["<C-g>"] = { "bzl_goto", mode = { "n", "i" } },
}

---Open the flat target picker over whatever `fetch` produces.
---`root` is captured by callers while the current buffer is still the
---user's file; picker callbacks run with the picker's own buffer current.
---@param root string|nil workspace root
---@param title string
---@param fetch fun(on_done: fun(targets: bzl.Target[]|nil))
---@param filter string|nil validated kind filter name
---@param project string|nil validated project scope
local function open_picker(root, title, fetch, filter, project)
	local ok, snacks = pcall(require, "snacks")
	if not ok then
		vim.notify("bzl.nvim: the target picker requires snacks.nvim", vim.log.levels.ERROR)
		return
	end

	local locate = make_locate(root)

	fetch(function(targets)
		targets = narrow(targets, filter, project)
		if not targets then
			return
		end
		snacks.picker.pick({
			title = title,
			items = M.make_items(targets),
			format = function(item)
				return { { item.label }, { " " }, { item.kind, "Comment" } }
			end,
			confirm = function(picker, item)
				act(picker, item, M.verb_for(item.kind))
			end,
			preview = function(ctx)
				return preview_target(ctx, locate)
			end,
			actions = {
				bzl_run = function(picker, item)
					act(picker, item, "run")
				end,
				bzl_test = function(picker, item)
					act(picker, item, "test")
				end,
				bzl_build = function(picker, item)
					act(picker, item, "build")
				end,
				bzl_goto = function(picker, item)
					goto_target(picker, item, locate)
				end,
			},
			win = { input = { keys = PICKER_KEYS } },
		})
	end)
end

---Open a flat picker over workspace targets. Arguments, in any order:
---a kind filter ("testable"/"runnable") and "here" to scope to the
---current project (nearest *.bazelproject directory, else the package).
function M.targets(...)
	local opts = parse_args(...)
	if not opts then
		return
	end
	local root = require("bzl.cli").workspace_root()
	local project
	if opts.here then
		project = resolve_project(root)
		if not project then
			return
		end
	end
	open_picker(root, title_for("Bazel targets", project, opts.filter), function(on_done)
		require("bzl.targets").list(on_done)
	end, opts.filter, project)
end

---Browse targets as a collapsible directory tree. Takes the same
---arguments as M.targets(); scoped trees open fully expanded.
---<CR> expands/collapses directories and acts on targets; on
---directories, bzl_test/bzl_build act on the whole subtree.
function M.tree(...)
	local opts = parse_args(...)
	if not opts then
		return
	end
	local ok, snacks = pcall(require, "snacks")
	if not ok then
		vim.notify("bzl.nvim: the target picker requires snacks.nvim", vim.log.levels.ERROR)
		return
	end

	local root = require("bzl.cli").workspace_root()
	local project
	if opts.here then
		project = resolve_project(root)
		if not project then
			return
		end
	end
	local locate = make_locate(root)

	require("bzl.targets").list(function(targets)
		targets = narrow(targets, opts.filter, project)
		if not targets then
			return
		end
		local tree = require("bzl.tree")
		local forest = tree.build(targets)
		-- scoped trees are small: open everything for flat-list speed
		if project then
			for _, node in ipairs(forest.nodes) do
				if node.dir then
					node.open = true
				end
			end
		end
		local searching = false

		---Wrap an action so it only applies to target leaves.
		local function leaf(action)
			return function(picker, item)
				if not item.dir then
					action(picker, item)
				end
			end
		end

		snacks.picker.pick({
			title = title_for("Bazel tree", project, opts.filter),
			-- a function finder: re-run on every picker:find(), which is
			-- how expand/collapse refreshes the list
			finder = function(_, ctx)
				-- while a pattern is typed, all nodes compete in the fuzzy
				-- match and matches keep their ancestors via keep_parents;
				-- otherwise show only the expanded part of the tree
				local searching_now = not ctx.filter:is_empty()
				ctx.picker.matcher.opts.keep_parents = searching_now
				local items = {}
				for _, node in ipairs(forest.nodes) do
					if searching_now or tree.visible(node) then
						items[#items + 1] = node
					end
				end
				return items
			end,
			sort = { fields = { "sort" } },
			filter = {
				-- trigger a re-find when the pattern flips empty/non-empty
				transform = function(_, filter)
					local searching_now = not filter:is_empty()
					if searching ~= searching_now then
						searching = searching_now
						return true
					end
				end,
			},
			format = function(item)
				local depth = 0
				local parent = item.parent
				while parent and not parent.root do
					depth = depth + 1
					parent = parent.parent
				end
				local indent = string.rep("  ", depth)
				if item.dir then
					local icon = item.open and " " or " "
					return { { indent }, { icon .. item.name, "SnacksPickerDirectory" } }
				end
				return { { indent }, { item.name }, { " " }, { item.kind, "Comment" } }
			end,
			confirm = function(picker, item)
				if item.dir then
					item.open = not item.open
					picker.list:set_target()
					picker:find()
				else
					act(picker, item, M.verb_for(item.kind))
				end
			end,
			preview = function(ctx)
				local item = ctx.item
				if not item.dir then
					return preview_target(ctx, locate)
				end
				if root then
					local dir = item.path == "" and root or (root .. "/" .. item.path)
					for _, build_name in ipairs({ "BUILD.bazel", "BUILD" }) do
						if vim.uv.fs_stat(dir .. "/" .. build_name) then
							item.file = dir .. "/" .. build_name
							item.pos = nil
							return require("snacks.picker.preview").file(ctx)
						end
					end
				end
				ctx.preview:notify("no BUILD file in //" .. item.path, "warn")
			end,
			actions = {
				bzl_run = leaf(function(picker, item)
					act(picker, item, "run")
				end),
				bzl_test = function(picker, item)
					if item.dir then
						-- like intellij's "run all tests in folder"
						picker:close()
						require("bzl.runner").execute("test", M.subtree_label(item.path))
					else
						act(picker, item, "test")
					end
				end,
				bzl_build = function(picker, item)
					if item.dir then
						picker:close()
						build(M.subtree_label(item.path))
					else
						act(picker, item, "build")
					end
				end,
				bzl_goto = leaf(function(picker, item)
					goto_target(picker, item, locate)
				end),
			},
			win = { input = { keys = PICKER_KEYS } },
		})
	end)
end

---Map targets to picker items. Pure function.
---`text` contains label and kind, so typing a kind narrows the picker.
---@param targets bzl.Target[]
---@return bzl.PickerItem[]
function M.make_items(targets)
	local items = {}
	for _, target in ipairs(targets) do
		items[#items + 1] = {
			text = target.label .. " " .. target.kind,
			label = target.label,
			kind = target.kind,
		}
	end

	return items
end

return M

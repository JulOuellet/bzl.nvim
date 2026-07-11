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

---Open a snacks picker over all targets in the current workspace.
---Requires snacks.nvim; reports an error if it is not installed.
function M.targets()
	local ok, snacks = pcall(require, "snacks")
	if not ok then
		vim.notify("bzl.nvim: the target picker requires snacks.nvim", vim.log.levels.ERROR)
		return
	end

	local root = require("bzl.cli").workspace_root()

	---Resolve and cache an item's BUILD file location on the item itself.
	---nil = not resolved yet, false = resolved but not found.
	---@param item bzl.PickerItem
	---@return { file: string, lnum: integer|nil }|nil
	local function locate(item)
		if not root then
			return nil
		end
		if item._location == nil then
			item._location = require("bzl.targets").location(item.label, root) or false
		end
		return item._location or nil
	end

	require("bzl.targets").list(function(targets)
		if not targets then
			return
		end
		snacks.picker.pick({
			title = "Bazel targets",
			items = M.make_items(targets),
			format = function(item)
				return { { item.label }, { " " }, { item.kind, "Comment" } }
			end,
			confirm = function(picker, item)
				act(picker, item, M.verb_for(item.kind))
			end,
			preview = function(ctx)
				local location = locate(ctx.item)
				if not location then
					ctx.preview:notify("no BUILD file found for " .. ctx.item.label, "warn")
					return
				end
				ctx.item.file = location.file
				ctx.item.pos = location.lnum and { location.lnum, 0 } or nil
				return require("snacks.picker.preview").file(ctx)
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
				end,
			},
			win = {
				input = {
					keys = {
						["<C-r>"] = { "bzl_run", mode = { "n", "i" } },
						["<C-t>"] = { "bzl_test", mode = { "n", "i" } },
						["<C-b>"] = { "bzl_build", mode = { "n", "i" } },
						["<C-g>"] = { "bzl_goto", mode = { "n", "i" } },
					},
				},
			},
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

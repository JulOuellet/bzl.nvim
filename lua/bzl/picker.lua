local M = {}

---@class bzl.PickerItem
---@field text string what the picker's fuzzy search matches against
---@field label string full target label, e.g. "//lib:greetings"
---@field kind string rule kind, e.g. "sh_test"

---Open a snacks picker over all targets in the current workspace.
---Requires snacks.nvim; reports an error if it is not installed.
function M.targets()
	local ok, snacks = pcall(require, "snacks")
	if not ok then
		vim.notify("bzl.nvim: the target picker requires snacks.nvim", vim.log.levels.ERROR)
		return
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
				picker:close()
				require("bzl.cli").run({ "build", item.label }, function(result)
					if result.code == 0 then
						vim.notify("bzl.nvim: built " .. item.label, vim.log.levels.INFO)
					else
						vim.notify(
							("bzl.nvim: build failed for %s\n%s"):format(item.label, result.stderr or ""),
							vim.log.levels.ERROR
						)
					end
				end)
			end,
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

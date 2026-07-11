local M = {}

---@class bzl.TreeNode
---@field text string fuzzy-match text
---@field sort string hierarchical sort key: parents' key + own segment
---@field name string display name (directory or target name)
---@field parent bzl.TreeNode|nil nil only for the internal root
---@field root boolean|nil internal root marker, never shown
---@field dir boolean|nil directory node
---@field open boolean|nil expansion state, mutable (directories only)
---@field path string|nil workspace-relative path (directories only)
---@field label string|nil target label (leaves only)
---@field kind string|nil rule kind (leaves only)

---Build the directory/target forest for a target list.
---Nodes are returned flat: hierarchy lives in `parent` links, display
---order in `sort` keys ("!" sorts directories above "#" targets), and
---expansion state in the mutable `open` flags of directory nodes.
---External labels are skipped.
---@param targets bzl.Target[]
---@return { nodes: bzl.TreeNode[], root: bzl.TreeNode }
function M.build(targets)
	local root = { root = true, dir = true, open = true, path = "", name = "//", text = "", sort = "" }
	local dirs = { [""] = root }
	local nodes = {} ---@type bzl.TreeNode[]

	local function dir_node(path)
		if dirs[path] then
			return dirs[path]
		end
		local parent_path, name = path:match("^(.*)/([^/]+)$")
		if not parent_path then
			parent_path, name = "", path
		end
		local parent = dir_node(parent_path)
		local node = {
			dir = true,
			open = false,
			path = path,
			name = name,
			text = "//" .. path,
			sort = parent.sort .. "!" .. name .. " ",
			parent = parent,
		}
		dirs[path] = node
		nodes[#nodes + 1] = node
		return node
	end

	for _, target in ipairs(targets) do
		local parsed = require("bzl.targets").parse_label(target.label)
		if parsed then
			local parent = dir_node(parsed.package)
			nodes[#nodes + 1] = {
				name = parsed.name,
				label = target.label,
				kind = target.kind,
				text = target.label .. " " .. target.kind,
				sort = parent.sort .. "#" .. parsed.name .. " ",
				parent = parent,
			}
		end
	end

	return { nodes = nodes, root = root }
end

---A node is visible when every ancestor directory is open.
---@param node bzl.TreeNode
---@return boolean
function M.visible(node)
	local parent = node.parent
	while parent and not parent.root do
		if not parent.open then
			return false
		end
		parent = parent.parent
	end
	return true
end

return M

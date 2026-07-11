local T = MiniTest.new_set()

local tree = require("bzl.tree")

local targets = {
	{ kind = "sh_binary", label = "//services/api:server" },
	{ kind = "sh_test", label = "//services/api:server_test" },
	{ kind = "sh_library", label = "//lib:util" },
	{ kind = "sh_binary", label = "//:tool" },
}

---@param forest { nodes: bzl.TreeNode[] }
local function by_text(forest)
	local index = {}
	for _, node in ipairs(forest.nodes) do
		index[node.text] = node
	end
	return index
end

T["build"] = MiniTest.new_set()

T["build"]["creates directory nodes with parent links"] = function()
	local nodes = by_text(tree.build(targets))
	local api = nodes["//services/api"]
	MiniTest.expect.equality(api.dir, true)
	MiniTest.expect.equality(api.parent.text, "//services")
	MiniTest.expect.equality(api.parent.parent.root, true)
	MiniTest.expect.equality(nodes["//services/api:server sh_binary"].parent, api)
	MiniTest.expect.equality(nodes["//:tool sh_binary"].parent.root, true)
end

T["build"]["sort keys order directories first, hierarchically"] = function()
	local keys = {}
	for _, node in ipairs(tree.build(targets).nodes) do
		keys[#keys + 1] = { sort = node.sort, name = node.name }
	end
	table.sort(keys, function(a, b)
		return a.sort < b.sort
	end)
	local names = vim.tbl_map(function(key)
		return key.name
	end, keys)
	MiniTest.expect.equality(names, { "lib", "util", "services", "api", "server", "server_test", "tool" })
end

T["visible"] = MiniTest.new_set()

T["visible"]["shows only the top level until directories open"] = function()
	local nodes = by_text(tree.build(targets))
	MiniTest.expect.equality(tree.visible(nodes["//services"]), true)
	MiniTest.expect.equality(tree.visible(nodes["//:tool sh_binary"]), true)
	MiniTest.expect.equality(tree.visible(nodes["//services/api"]), false)
	MiniTest.expect.equality(tree.visible(nodes["//services/api:server sh_binary"]), false)

	nodes["//services"].open = true
	MiniTest.expect.equality(tree.visible(nodes["//services/api"]), true)
	MiniTest.expect.equality(tree.visible(nodes["//services/api:server sh_binary"]), false)

	nodes["//services/api"].open = true
	MiniTest.expect.equality(tree.visible(nodes["//services/api:server sh_binary"]), true)
end

return T

local group = vim.env.BZL_TEST_GROUP
if not group then
	MiniTest.run()
	return
end

local files = vim.fn.globpath("tests", "**/test_*.lua", true, true)
local selected = {}
for _, file in ipairs(files) do
	local go = file:match("test_go_integration%.lua$") ~= nil
	local python = file:match("test_python_integration%.lua$") ~= nil
	if (group == "core" and not go and not python) or (group == "go" and go) or (group == "python" and python) then
		selected[#selected + 1] = file
	end
end

MiniTest.run({ collect = {
	find_files = function()
		return selected
	end,
} })

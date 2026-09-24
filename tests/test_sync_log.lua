local child = MiniTest.new_child_neovim()
local eq = MiniTest.expect.equality
local T = MiniTest.new_set({
	hooks = {
		pre_case = function()
			child.restart({ "-u", "scripts/minimal_init.lua" })
			child.lua([[
				_G.editor = vim.api.nvim_get_current_win()
				_G.logs = require("bzl.sync_log")
				_G.log = logs.start("/workspace")
				_G.buf = log.buf
				_G.win = vim.fn.win_findbuf(buf)[1]
				_G.lines = function()
					return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
				end
			]])
		end,
		post_once = child.stop,
	},
})

T["keeps focus, follows output, and lets the user scroll back"] = function()
	eq(child.lua_get("vim.api.nvim_get_current_win() == editor"), true)
	eq(child.lua_get("vim.bo[buf].modifiable"), false)
	child.lua([[log:append("first\nsecond\nthird")]])
	eq(child.lua_get("vim.api.nvim_win_get_cursor(win)[1] == #lines()"), true)
	child.lua([[
		vim.api.nvim_win_set_cursor(win, { 1, 0 })
		log:append("fourth")
	]])
	eq(child.lua_get("vim.api.nvim_win_get_cursor(win)[1]"), 1)
end

T["joins chunks, strips colours, and flushes the final unterminated line"] = function()
	child.lua([[
		local stream = log:stderr()
		stream("\27[3")
		stream("2mLoading: one\27[0m\r")
		stream("\nLoading: tw")
		stream("o\nfinal")
		stream(nil)
	]])
	eq(child.lua_get("vim.list_slice(lines(), 3)"), { "Loading: one", "Loading: two", "final" })
end

T["updates elapsed time while quiet and stops after completion"] = function()
	child.lua([[
		local defer = vim.defer_fn
		local ticks = {}
		vim.defer_fn = function(callback, delay)
			assert(delay == 1000)
			ticks[#ticks + 1] = callback
		end
		local timed = logs.start("/timed")
		local timed_buf = timed.buf
		local before = vim.b[timed_buf].bzl_sync_status
		timed.started = vim.uv.hrtime() - 2e9
		ticks[1]()
		assert(vim.b[timed_buf].bzl_sync_status ~= before)
		assert(#ticks == 2)
		timed:finish("Sync failed")
		_G.finished = vim.b[timed_buf].bzl_sync_status
		ticks[2]()
		assert(#ticks == 2)
		_G.timed_buf = timed_buf
		vim.defer_fn = defer
	]])
	eq(child.lua_get("vim.b[timed_buf].bzl_sync_status"), child.lua_get("finished"))
	eq(child.lua_get("finished:find('Sync failed', 1, true) ~= nil"), true)
end

T["closing keeps collecting and the command reopens without starting a sync"] = function()
	child.lua([[
		vim.api.nvim_set_current_win(win)
		vim.cmd("Bzl sync log") -- The log buffer carries its workspace.
		vim.cmd("normal q")
		vim.api.nvim_set_current_win(editor)
		log:append("output while hidden")
		log:finish("Synced 2 targets")
		vim.b.bzl_workspace_root = "/workspace"
		vim.cmd("Bzl sync log")
	]])
	eq(child.lua_get("#vim.fn.win_findbuf(buf)"), 1)
	eq(child.lua_get("vim.api.nvim_get_current_win() == editor"), true)
	eq(child.lua_get("lines()[#lines() - 1]"), "output while hidden")
	eq(child.lua_get("lines()[#lines()]:find('Synced 2 targets', 1, true) ~= nil"), true)
end

T["reuses the workspace log on the next sync and keeps other workspaces separate"] = function()
	child.lua([[
		log:append("old output")
		log:finish("Synced")
		_G.next_log = logs.start("/workspace")
		_G.other = logs.start("/other")
		next_log:append("first workspace")
		other:append("second workspace")
	]])
	eq(child.lua_get("next_log.buf == buf"), true)
	eq(child.lua_get("#vim.fn.win_findbuf(buf)"), 1)
	eq(child.lua_get([[table.concat(lines(), '\n'):find('old output', 1, true) == nil]]), true)
	eq(child.lua_get("lines()[#lines()]"), "first workspace")
	eq(child.lua_get("vim.api.nvim_buf_get_lines(other.buf, -2, -1, false)[1]"), "second workspace")
end

T["opens in the current tab without replacing a repurposed window"] = function()
	child.lua([[
		_G.user_buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_win_set_buf(win, user_buf)
		logs.open("/workspace")
	]])
	eq(child.lua_get("vim.api.nvim_win_get_buf(win) == user_buf"), true)
	child.cmd("tabnew")
	child.lua([[logs.open("/workspace")]])
	eq(child.lua_get("#vim.api.nvim_tabpage_list_wins(0)"), 2)
end

T["wiping the buffer does not interrupt progress or completion"] = function()
	child.lua([[
		vim.api.nvim_buf_delete(buf, { force = true })
		log:append("later output")
		log:stage("Building")
		log:finish("Synced")
		_G.next_log = logs.start("/workspace")
	]])
	eq(child.lua_get("vim.api.nvim_buf_is_valid(next_log.buf)"), true)
end

return T

local M = {}

---@alias bzl.Verb "run"|"test"|"build"

---@class bzl.RunnerState
---@field win integer|nil runner split window
---@field buf integer|nil terminal buffer of the current run
---@field job integer|nil job id while a run is in flight
local state = {}

---Open the runner split, reusing it if still on screen. Focus stays
---in the caller's window.
---@return integer win
---@return boolean created
local function ensure_window()
	if
		state.win
		and state.buf
		and vim.api.nvim_win_is_valid(state.win)
		and vim.api.nvim_buf_is_valid(state.buf)
		and vim.api.nvim_win_get_tabpage(state.win) == vim.api.nvim_get_current_tabpage()
		and vim.api.nvim_win_get_buf(state.win) == state.buf
	then
		return state.win, false
	end
	local prev = vim.api.nvim_get_current_win()
	vim.cmd(("botright %dsplit"):format(require("bzl.config").get().runner.height))
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_set_current_win(prev)
	return win, true
end

---Run a bazel verb on a target label, streaming output into a terminal split.
---Any run still in flight is stopped and its buffer replaced.
---@param root string|nil workspace root
---@param verb bzl.Verb
---@param label string
function M.execute(root, verb, label)
	if not root then
		vim.notify(
			"bzl.nvim: no bazel workspace found (no MODULE.bazel or WORKSPACE above this file)",
			vim.log.levels.ERROR
		)
		return
	end

	if state.job then
		pcall(vim.fn.jobstop, state.job)
		state.job = nil
	end
	local prev_win = state.win
	local prev_buf = state.buf

	local win, created = ensure_window()
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(win, buf)

	local cmd = require("bzl.cli").command({ verb, label })
	local started
	local job
	vim.api.nvim_win_call(win, function()
		-- term = true converts the (current) buffer into a terminal
		started, job = pcall(vim.fn.jobstart, cmd, {
			cwd = root,
			term = true,
			on_exit = function()
				-- guard: a newer run may own state.job by the time this fires
				if state.job == job then
					state.job = nil
				end
			end,
		})
		if started then
			-- cursor on the last line makes the terminal follow the output
			vim.cmd("normal! G")
		end
	end)

	if not started or job <= 0 then
		if created then
			vim.api.nvim_win_close(win, true)
		elseif prev_buf and vim.api.nvim_buf_is_valid(prev_buf) then
			vim.api.nvim_win_set_buf(win, prev_buf)
		end
		if vim.api.nvim_buf_is_valid(buf) then
			vim.api.nvim_buf_delete(buf, { force = true })
		end
		vim.notify(("bzl.nvim: could not run %q"):format(cmd[1]), vim.log.levels.ERROR)
		return
	end

	if
		prev_win
		and prev_win ~= win
		and prev_buf
		and vim.api.nvim_win_is_valid(prev_win)
		and vim.api.nvim_buf_is_valid(prev_buf)
		and vim.api.nvim_win_get_buf(prev_win) == prev_buf
	then
		vim.api.nvim_win_close(prev_win, true)
	end
	if prev_buf and vim.api.nvim_buf_is_valid(prev_buf) then
		vim.api.nvim_buf_delete(prev_buf, { force = true })
	end

	state.win = win
	state.buf = buf
	state.job = job
end

return M

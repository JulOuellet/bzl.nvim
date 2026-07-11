local M = {}

---@alias bzl.Verb "run"|"test"|"build"

---@class bzl.RunnerState
---@field win integer|nil runner split window
---@field buf integer|nil terminal buffer of the current/last run
---@field job integer|nil job id while a run is in flight
---@field last { verb: bzl.Verb, label: string }|nil
local state = {}

---Open the runner split, reusing it if still on screen. Focus stays
---in the caller's window.
---@return integer win
local function ensure_window()
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		return state.win
	end
	local prev = vim.api.nvim_get_current_win()
	vim.cmd(("botright %dsplit"):format(require("bzl.config").get().runner.height))
	state.win = vim.api.nvim_get_current_win()
	vim.api.nvim_set_current_win(prev)
	return state.win
end

---Run a bazel verb on a target label, streaming output into a terminal split.
---Any run still in flight is stopped and its buffer replaced.
---@param verb bzl.Verb
---@param label string
function M.execute(verb, label)
	local root = require("bzl.cli").workspace_root()
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
	local prev_buf = state.buf

	local win = ensure_window()
	state.buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(win, state.buf)

	local cmd = { require("bzl.config").get().bazel_cmd, verb, label }
	local job
	vim.api.nvim_win_call(win, function()
		-- term = true converts the (current) buffer into a terminal
		job = vim.fn.jobstart(cmd, {
			cwd = root,
			term = true,
			on_exit = function()
				-- guard: a newer run may own state.job by the time this fires
				if state.job == job then
					state.job = nil
				end
			end,
		})
		-- cursor on the last line makes the terminal follow the output
		vim.cmd("normal! G")
	end)

	if prev_buf and vim.api.nvim_buf_is_valid(prev_buf) then
		vim.api.nvim_buf_delete(prev_buf, { force = true })
	end

	if job <= 0 then
		vim.notify(("bzl.nvim: could not run %q"):format(cmd[1]), vim.log.levels.ERROR)
		return
	end

	state.job = job
	state.last = { verb = verb, label = label }
end

---Repeat the most recent execute().
function M.rerun()
	if not state.last then
		vim.notify("bzl.nvim: nothing to re-run yet", vim.log.levels.WARN)
		return
	end
	M.execute(state.last.verb, state.last.label)
end

return M

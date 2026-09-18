local M = {}
local logs = {}
local Log = {}
Log.__index = Log

function Log:append(text)
	if not vim.api.nvim_buf_is_valid(self.buf) then
		return -- Wiping the log must not interrupt sync.
	end
	-- Bazel may emit terminal colours or carriage-return progress updates.
	text = text:gsub("\27%[[%d;?]*[A-Za-z]", ""):gsub("\r", "\n")
	local lines = vim.split(text, "\n", { trimempty = true })
	if #lines == 0 then
		return
	end
	local count = vim.api.nvim_buf_line_count(self.buf)
	local following = {}
	for _, win in ipairs(vim.fn.win_findbuf(self.buf)) do
		if vim.api.nvim_win_get_cursor(win)[1] == count then
			following[#following + 1] = win
		end
	end
	vim.bo[self.buf].modifiable = true
	vim.api.nvim_buf_set_lines(self.buf, -1, -1, false, lines)
	vim.bo[self.buf].modifiable = false
	for _, win in ipairs(following) do
		vim.api.nvim_win_set_cursor(win, { count + #lines, 0 })
	end
end

function Log:elapsed()
	return (vim.uv.hrtime() - self.started) / 1e9
end

function Log:status()
	if vim.api.nvim_buf_is_valid(self.buf) then
		vim.b[self.buf].bzl_sync_status = ("Bazel sync: %s | %.0fs"):format(self.phase, self:elapsed())
		vim.cmd("redrawstatus")
	end
end

function Log:stage(message)
	self.phase = message
	self:append(("[%.1fs] %s"):format(self:elapsed(), message))
	self:status()
end

---Each command gets its own line accumulator, flushed by the EOF callback.
function Log:stderr()
	local pending = ""
	return function(data)
		pending = pending .. (data or "")
		local complete, rest = pending:match("^(.*[\r\n])(.-)$")
		if complete then
			self:append(complete)
			pending = rest
		end
		if not data then
			self:append(pending)
			pending = ""
		end
	end
end

function Log:finish(message)
	self.running = false
	self:stage(message)
end

---Show the latest log for this workspace without moving focus.
function M.open(root)
	local log = logs[root]
	if not log or not vim.api.nvim_buf_is_valid(log.buf) then
		vim.notify("bzl.nvim: no sync log for this workspace; run :Bzl sync first", vim.log.levels.INFO)
		return
	end
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_get_buf(win) == log.buf then
			return
		end
	end
	local previous = vim.api.nvim_get_current_win()
	vim.cmd(("botright %dsplit"):format(require("bzl.config").get().sync.height))
	local win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_buf(win, log.buf)
	vim.wo[win].winbar = "%{get(b:, 'bzl_sync_status', '')}"
	vim.wo[win].wrap = false
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.api.nvim_win_set_cursor(win, { vim.api.nvim_buf_line_count(log.buf), 0 })
	vim.api.nvim_set_current_win(previous)
end

function M.start(root)
	local previous = logs[root]
	local buf = previous and previous.buf
	if not buf or not vim.api.nvim_buf_is_valid(buf) then
		buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(buf, "bzl://sync" .. root)
		vim.bo[buf].bufhidden = "hide"
		vim.bo[buf].filetype = "bzl-sync"
		vim.b[buf].bzl_workspace_root = root
		vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true, desc = "Close sync log" })
	end
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Workspace: " .. root })
	vim.bo[buf].modifiable = false
	local log = setmetatable({ buf = buf, started = vim.uv.hrtime(), running = true }, Log)
	logs[root] = log
	log:stage("Discovering targets")
	M.open(root)
	local function tick()
		if log.running then
			log:status()
			vim.defer_fn(tick, 1000)
		end
	end
	vim.defer_fn(tick, 1000)
	return log
end

return M

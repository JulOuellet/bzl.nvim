local eq = MiniTest.expect.equality
local cli = require("bzl.cli")
local original, targets, calls
local T = MiniTest.new_set({
	hooks = {
		pre_case = function()
			package.loaded["bzl.targets"] = nil
			targets = require("bzl.targets")
			calls, original = {}, cli.run
			cli.run = function(root, args, done)
				local call = { root = root, args = args, done = done }
				calls[#calls + 1] = call
				return {
					cancel = function()
						call.cancelled = true
					end,
				}
			end
		end,
		post_case = function()
			targets.refresh()
			cli.run = original
			package.loaded["bzl.targets"] = nil
		end,
	},
})

local function complete(index, label)
	calls[index].done({ code = 0, stdout = "py_binary rule " .. label })
end

T["same query coalesces and keeps distinct scopes separate"] = function()
	local results = {}
	local function done(value)
		results[#results + 1] = value
	end
	targets.list("/ws", done)
	targets.list("/ws", done)
	targets.list("/ws", done, { scope = { "//python/..." } })
	eq(#calls, 2)
	complete(1, "//:app")
	complete(2, "//python:app")
	eq(#results, 3)
	eq(results[1], results[2])
end

T["root invalidation rejects late results without touching another workspace"] = function()
	local cancelled, other, newest
	targets.list("/ws", function(value)
		cancelled = value == nil
	end)
	targets.list("/other", function(value)
		other = value
	end)
	targets.refresh("/ws")
	eq(calls[1].cancelled, true)
	eq(calls[2].cancelled, nil)
	targets.list("/ws", function(value)
		newest = value
	end)
	complete(1, "//:obsolete")
	complete(2, "//:other")
	complete(3, "//:new")
	eq(
		vim.wait(1000, function()
			return cancelled
		end, 10),
		true
	)
	eq(other[1].label, "//:other")
	eq(newest[1].label, "//:new")
end

T["queued cache hits cannot resurrect invalidated target lists"] = function()
	targets.list("/ws", function() end)
	complete(1, "//:old")
	local called, result
	targets.list("/ws", function(value)
		called, result = true, value
	end)
	targets.refresh("/ws")
	eq(
		vim.wait(1000, function()
			return called
		end, 10),
		true
	)
	eq(result, nil)
end

return T

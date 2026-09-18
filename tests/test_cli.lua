local T = MiniTest.new_set({ hooks = {
	post_case = function()
		require("bzl.config").setup()
	end,
} })

T["places startup and build flags in the correct positions"] = function()
	require("bzl.config").setup({
		bazel_cmd = "bazelisk",
		startup_flags = { "--output_base=/tmp/bazel output" },
		build_flags = { "--config=dev", "--define=variant=one" },
	})
	local command = require("bzl.cli").command
	for _, verb in ipairs({ "build", "test", "run", "cquery", "info" }) do
		MiniTest.expect.equality(command({ verb, "//:app" }), {
			"bazelisk",
			"--output_base=/tmp/bazel output",
			verb,
			"--config=dev",
			"--define=variant=one",
			"//:app",
		})
	end
	MiniTest.expect.equality(
		command({ "query", "//..." }),
		{ "bazelisk", "--output_base=/tmp/bazel output", "query", "//..." }
	)
end

T["streams stderr before exit while retaining complete command output"] = function()
	if vim.fn.has("win32") == 1 then
		MiniTest.skip("POSIX test process")
	end
	local chunks, result, ended = {}, nil, false
	local process = require("bzl.cli").system({
		"sh",
		"-c",
		"printf 'Loading: first\\n' >&2; read -r line; printf 'last error' >&2; printf 'query data\\n'; exit 7",
	}, { stdin = true }, function(output)
		MiniTest.expect.equality(vim.in_fast_event(), false)
		MiniTest.expect.equality(ended, true)
		result = output
	end, function(data)
		MiniTest.expect.equality(vim.in_fast_event(), false)
		if data then
			chunks[#chunks + 1] = data
		else
			ended = true
		end
	end)
	local streamed = vim.wait(5000, function()
		return #chunks > 0
	end)
	local before_exit = result == nil
	process:write("continue\n")
	process:write(nil)
	local completed = vim.wait(5000, function()
		return result ~= nil
	end)
	if not completed then
		process:kill(9)
	end
	MiniTest.expect.equality(streamed and before_exit and completed, true)
	MiniTest.expect.equality(result.code, 7)
	MiniTest.expect.equality(result.stdout, "query data\n")
	MiniTest.expect.equality(result.stderr, "Loading: first\nlast error")
	MiniTest.expect.equality(table.concat(chunks), result.stderr)
end

return T

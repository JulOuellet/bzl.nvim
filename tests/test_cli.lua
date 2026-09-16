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

return T

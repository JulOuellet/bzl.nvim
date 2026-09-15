local T = MiniTest.new_set()
local eq = MiniTest.expect.equality
local cache = require("bzl.sync.cache")
local config = require("bzl.config")
local tmp, directory
T = MiniTest.new_set({
	hooks = {
		pre_case = function()
			tmp = vim.fn.tempname()
			vim.fn.mkdir(tmp, "p")
			directory = cache.directory
			cache.directory = function()
				return tmp .. "/cache"
			end
			config.setup()
		end,
		post_case = function()
			cache.directory = directory
			config.setup()
			vim.fn.delete(tmp, "rf")
		end,
	},
})

T["key is independent of shared scope table identity"] = function()
	local ctx = require("bzl.sync").context(tmp)
	eq(cache.key(ctx), cache.key(require("bzl.sync").context(tmp, vim.deepcopy(ctx.scope))))
end

T["scoped metadata restores from disk with matching configuration"] = function()
	local ctx = require("bzl.sync").context(tmp, { "//python/..." })
	local entry = { version = cache.version, key = ctx.key, root = tmp, scope = ctx.scope, inputs = {}, adapters = {} }
	eq(cache.save(ctx, entry), true)
	eq(cache.load_latest(require("bzl.sync").context(tmp)), entry)
	config.setup({ command_args = { build = { "--config=other" } } })
	eq(cache.load_latest(require("bzl.sync").context(tmp)), nil)
end

T["corrupt cache and incompatible schemas are ignored"] = function()
	local ctx = require("bzl.sync").context(tmp)
	cache.save(ctx, { version = -1, key = ctx.key, adapters = {} })
	eq(cache.load(ctx), nil)
	vim.fn.writefile({ "not json" }, cache.path(ctx))
	eq(cache.load(ctx), nil)
end

T["content fingerprints detect changed exports even with unchanged size"] = function()
	local file = tmp .. "/compile_commands.json"
	vim.fn.writefile({ "old" }, file)
	local entry =
		{ adapters = { cpp = { metadata = { files = { file }, fingerprints = { [file] = cache.stamp(file) } } } } }
	eq(cache.valid_files(entry), true)
	vim.fn.writefile({ "new" }, file)
	eq(cache.valid_files(entry), false)
	vim.fn.delete(file)
	eq(cache.valid_files(entry), false)
end

T["snapshot hashes local and canonical external inputs plus explicit inputs"] = function()
	vim.fn.mkdir(tmp .. "/output/external/repo/pkg", "p")
	vim.fn.writefile({ "build" }, tmp .. "/BUILD.bazel")
	vim.fn.writefile({ "rule" }, tmp .. "/output/external/repo/pkg/defs.bzl")
	vim.fn.writefile({ "requirements_lock = '//:lock.txt'" }, tmp .. "/MODULE.bazel")
	vim.fn.writefile({ "pins" }, tmp .. "/lock.txt")
	config.setup({ sync = { inputs = { "other.rc" } } })
	local ctx = require("bzl.sync").context(tmp)
	ctx.run = function(args, done)
		done({ code = 0, stdout = args[1] == "info" and tmp .. "/output\n" or "//:BUILD.bazel\n@@repo//pkg:defs.bzl\n" })
	end
	local inputs
	cache.snapshot(ctx, function(value)
		inputs = value
	end)
	eq(inputs[tmp .. "/BUILD.bazel"], cache.stamp(tmp .. "/BUILD.bazel"))
	eq(inputs[tmp .. "/output/external/repo/pkg/defs.bzl"], cache.stamp(tmp .. "/output/external/repo/pkg/defs.bzl"))
	eq(inputs[tmp .. "/lock.txt"], cache.stamp(tmp .. "/lock.txt"))
	eq(inputs[tmp .. "/other.rc"], false)
end

return T

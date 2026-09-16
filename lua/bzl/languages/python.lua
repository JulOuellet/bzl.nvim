local M = {}
local query_file = vim.fs.joinpath(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)), "../../../bazel/python.cquery")

local function labels(ctx)
	local selected = vim.list_slice(ctx.config.python.targets)
	if #selected == 0 then
		for _, target in ipairs(ctx.targets) do
			if target.kind:match("^py_") then
				selected[#selected + 1] = target.label
			end
		end
		table.sort(selected)
	end
	return selected
end

function M.detect(ctx)
	return #labels(ctx) > 0
end

function M.prepare(ctx, done)
	local selected = labels(ctx)
	if #selected == 0 then
		done({ paths = {}, targets = 0, summary = "0 python paths" })
		return
	end
	for _, label in ipairs(selected) do
		if type(label) ~= "string" or not label:match("^[@/]") or label:find("[%s\"'()]") then
			done(nil, "invalid Python target pattern: " .. tostring(label))
			return
		end
	end
	local expression = "config(set(" .. table.concat(selected, " ") .. "), target)"
	ctx.run({ "cquery", expression, "--output=starlark", "--starlark:file=" .. query_file }, function(output)
		local records, err = require("bzl.python.model").parse(output)
		if not records or #records == 0 then
			done(nil, err or "selected targets do not expose PyInfo")
			return
		end
		vim.notify(("bzl.nvim: building %d Python targets..."):format(#records), vim.log.levels.INFO)
		local build = { "build", "--output_groups=+compilation_outputs", "--remote_download_outputs=all" }
		for _, record in ipairs(records) do
			build[#build + 1] = record.label
		end
		ctx.run(build, function()
			ctx.run({ "info", "execution_root" }, function(info)
				local execution_root = vim.trim(info)
				if execution_root == "" or execution_root:sub(1, 1) ~= "/" then
					done(nil, "bazel info returned an invalid execution_root")
					return
				end
				local model, resolve_err = require("bzl.python.model").resolve(records, ctx.root, execution_root)
				if model then
					model.summary = ("%d python paths"):format(#model.paths)
				end
				done(model, resolve_err)
			end)
		end)
	end)
end

function M.apply(client, root, model)
	return require("bzl.python.lsp").apply(client, root, model)
end

return M

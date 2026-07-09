.PHONY: test fmt fmt-check deps

deps: deps/mini.nvim

deps/mini.nvim:
	git clone --filter=blob:none --depth 1 https://github.com/echasnovski/mini.nvim $@

test: deps
	nvim --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run()"

fmt:
	stylua .

fmt-check:
	stylua --check .

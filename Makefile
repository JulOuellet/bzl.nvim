.PHONY: test fmt fmt-check deps test-integration-python test-integration-go

deps: deps/mini.nvim

deps/mini.nvim:
	git clone --filter=blob:none --depth 1 https://github.com/echasnovski/mini.nvim $@

test: deps
	nvim --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run()"

fmt:
	stylua .

fmt-check:
	stylua --check .

test-integration-python:
	cd examples/multilang && nvim --headless -u NONE -i NONE -l "$(CURDIR)/tests/integration/python.lua"

test-integration-go:
	cd examples/multilang && nvim --headless -u NONE -i NONE -l "$(CURDIR)/tests/integration/go.lua"

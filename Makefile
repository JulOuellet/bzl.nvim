.PHONY: test .test-core .test-go-integration .test-python-integration fmt fmt-check deps

deps: deps/mini.nvim

deps/mini.nvim:
	git clone --filter=blob:none --depth 1 https://github.com/echasnovski/mini.nvim $@

test: deps
	$(MAKE) --no-print-directory --output-sync=target -j3 .test-core .test-go-integration .test-python-integration

.test-core: deps
	BZL_TEST_GROUP=core nvim --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run()"

.test-go-integration: deps
	BZL_TEST_GROUP=go nvim --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run()"

.test-python-integration: deps
	BZL_TEST_GROUP=python nvim --headless --noplugin -u scripts/minimal_init.lua -c "lua MiniTest.run()"

fmt:
	stylua .

fmt-check:
	stylua --check .

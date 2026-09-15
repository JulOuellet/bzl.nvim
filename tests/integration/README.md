# Opt-in integration tests

These tests use the standalone `examples/multilang` workspace. They do not run
under `make test`, need network access on a cold Bazel cache, and can download
large toolchains. Run only in a trusted workspace. Do not run tests that mutate
the same workspace concurrently.

The `opt-in integration` GitHub Actions workflow runs only when manually
dispatched. It pins server versions and includes the Bazel smoke tests.

From the plugin root, with Neovim >= 0.11 and Bazel 8.7.0 available:

```sh
make test-integration-python
BZL_TEST_LSP_NAME=basedpyright BZL_TEST_LSP=basedpyright-langserver make test-integration-python
make test-integration-go
```

The Python test starts its own clean LSP client, asserts missing first-party
and generated imports before sync, then checks that sync resolves them and
retains the intentional argument-type diagnostic. It checks first-party,
wheel and generated definitions, typed hover, user-owned paths, and restoration
from disk after reloading the coordinator. It uses push diagnostics explicitly
to keep the harness comparable across Neovim versions; the plugin does not
change diagnostic capabilities or suppress errors.

Tested binaries: Pyright 1.1.411 and basedpyright 1.39.8. Set `BZL_TEST_LSP` to
an executable path to use your installation. The Go test builds the pinned
rules_go package driver, sends a real JSON request, and checks that the response
contains the Bazel-only local dependency. It does not yet test a running gopls.

On NixOS, from `examples/multilang`:

```sh
nix run path:. -- env BZL_TEST_LSP=/absolute/path/to/pyright-langserver \
  nvim --headless -u NONE -i NONE -l "$PWD/../../tests/integration/python.lua"
nix run path:. -- nvim --headless -u NONE -i NONE -l "$PWD/../../tests/integration/go.lua"
```

The fixture's pinned Nixpkgs revision supplies the tested versions as `pyright`
and `basedpyright`. The Nix shell does not install these servers by default.
Tests use private temporary plugin caches and remove them afterward. Bazel's
download/build caches remain reusable. Neither test edits user LSP settings.

Remaining acceptance work: clangd, gopls and rust-analyzer protocol tests;
Neovim restart in a separate process; conflicting target environments;
rules_python 2.x/venv layouts; non-Linux platforms. The Rust exporter smoke
command is `bazel run @rules_rust//tools/rust_analyzer:gen_rust_project -- //rust/...`.

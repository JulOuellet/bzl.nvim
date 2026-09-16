# bzl.nvim

[![ci](https://github.com/JulOuellet/bzl.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/JulOuellet/bzl.nvim/actions/workflows/ci.yml)

Bazel integration for Neovim: browse, run, test, and build bazel targets from a
[snacks.nvim](https://github.com/folke/snacks.nvim) picker, with streaming
output and LSP support for bazel-managed dependencies.


## Features

- Fuzzy picker over all workspace targets
- Filter by testable (`*_test`) or runnable (`*_binary`) rule kinds
- Scope the picker to the current project (nearest `*.bazelproject`
  directory, or the current package)
- Run, test, and build targets; run and test output streams into a
  reusable terminal split
- Toggle a target's BUILD definition preview while browsing; jump to it directly
- `:Bzl sync` refreshes targets and configures the language server to
  resolve bazel-managed dependencies (see
  [supported languages](#supported-languages))
- Target cache invalidates automatically when BUILD files are written

## Status

Early development (pre-1.0). Commands and configuration may change between
minor versions.

## Requirements

- Neovim >= 0.10
- bazel or bazelisk on your PATH (or set `bazel_cmd`)
- [snacks.nvim](https://github.com/folke/snacks.nvim) for the picker
- [pyright](https://github.com/microsoft/pyright) or basedpyright, for
  Python language support

## Installation

With [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
	"JulOuellet/bzl.nvim",
	dependencies = { "folke/snacks.nvim" },
	cmd = "Bzl",
	opts = {},
}
```

With Neovim's built-in package manager (0.12+):

```lua
vim.pack.add({
	"https://github.com/folke/snacks.nvim",
	"https://github.com/JulOuellet/bzl.nvim",
})
```

Calling `setup()` (or using `opts`) is optional; defaults apply otherwise.

## Commands

| Command | Description |
| --- | --- |
| `:Bzl targets [testable\|runnable] [here]` | Flat fuzzy picker over targets |
| `:Bzl sync` | Refresh targets, build the selected Python project, and update its language servers |

Arguments can be combined in any order:

- `testable` — only `*_test` targets
- `runnable` — only `*_binary` targets
- `here` — scope to the current project: the nearest directory containing
  a `*.bazelproject` view file, or the current package when none exists.

## Picker keys

| Key | Action |
| --- | --- |
| `<CR>` | Test, run, or build, chosen by rule kind |
| `<C-t>` | `bazel test` |
| `<C-r>` | `bazel run` |
| `<C-b>` | `bazel build` (background, notifies result) |
| `<C-g>` | Jump to the target's BUILD definition |
| `<A-p>` | Toggle the BUILD-file preview panel |

The picker opens as a single target-list panel; use `<A-p>` when a BUILD-file
preview is useful. Run and test output streams into a terminal split at the
bottom; builds run in the background and report through `vim.notify`.

## Suggested keymaps

No global keymaps are created. A minimal set of mappings:

```lua
keys = {
	{ "<leader>bs", "<cmd>Bzl sync<cr>", desc = "Bazel Sync" },
	{ "<leader>bt", "<cmd>Bzl targets<cr>", desc = "Bazel Targets" },
	{ "<leader>bh", "<cmd>Bzl targets here<cr>", desc = "Bazel Targets (here)" },
},
```

## Supported languages

Browsing, running, testing, and building targets is language-agnostic:
every target `bazel query` returns shows up in the picker, whatever
language it builds. Language support below refers to `:Bzl sync`
configuring the language server to resolve imports that bazel manages;
Python is the only language wired up so far.

### Python

`:Bzl sync` queries the selected targets' configured `PyInfo` providers,
builds their default and `compilation_outputs` output groups, and then updates
Pyright/Basedpyright. It resolves `select()` with your build flags and obtains
transitive import roots from Bazel, including pip dependencies and generated
Python sources. A fresh checkout does not need a separate build first.
Sync can download dependencies and execute build actions; it does not run tests.

By default, sync selects the workspace's `py_*` rules. For a monorepo, select
the binaries, tests, or libraries you are working on:

```lua
require("bzl").setup({
	python = { targets = { "//services/api:server" } },
	build_flags = { "--config=dev" }, -- must exist in your .bazelrc
})
```

Target patterns such as `//services/api/...` are accepted. Explicit selections
also support custom rules exposing `PyInfo`; generated sources must be included
in their default or `compilation_outputs` output groups. `.bazelproject` contents
are not interpreted. Startup and build flags also apply to picker builds,
runs, and tests, so those use the same configuration as sync.

Discovered paths are sent as `python.analysis.extraPaths` to Pyright and
`basedpyright.analysis.extraPaths` to Basedpyright. Existing user paths and
unrelated settings are preserved; subsequent syncs remove obsolete paths added
by the plugin. When a selected binary or test exposes a Python runtime, sync
also sets `python.pythonPath` unless you have configured an interpreter yourself.
Selecting libraries alone may not expose runtime information.

The last successful result is kept in memory and applied when a Python server
attaches or restarts. Failed discovery/builds and edits made during sync leave
the previous LSP configuration in place. Run sync again after changing BUILD
files, dependencies, target selection, or flags. Clients shared with another
Bazel workspace are not updated. `:checkhealth bzl` reports the saved model.

Python sync requires Bazel 8+ and is tested with rules_python 1.6.3, Pyright, and
Basedpyright. Native providers and other rules_python versions are recognized
through provider names rather than repository naming conventions. Unsupported
metadata or missing generated files cause an explicit sync failure.

The language server sees the union of the selected targets' import paths, not
Bazel's per-target dependency visibility. Select a single target when projects
need conflicting package versions; selections with conflicting Python runtimes
are rejected. Existing `pyrightconfig.json` / `pyproject.toml` execution
environments or import-path settings can take precedence over LSP settings;
sync does not rewrite these files. It does not enforce Bazel strict dependencies.

## Configuration

Defaults:

```lua
require("bzl").setup({
	-- Binary used for all bazel invocations, e.g. "bazelisk" or an absolute path.
	bazel_cmd = "bazel",
	startup_flags = {}, -- before the Bazel subcommand, e.g. --output_base=...
	build_flags = {}, -- used by build/run/test, cquery, and info
	python = {
		targets = {}, -- empty selects all workspace py_* rules
	},
	picker = {
		-- Show the BUILD-file preview panel when the picker opens.
		preview = false,
	},
	runner = {
		-- Height of the terminal split that shows run/test output.
		height = 15,
	},
})
```

The preview remains available through `<A-p>` when `picker.preview` is false.

## Health

`:checkhealth bzl` verifies the Neovim version, the bazel binary, and the
snacks.nvim dependency, and reports the last successful Python sync for the
current workspace.

## Development

With nix, `nix develop` provides bazel, Python 3, stylua, and make. Otherwise,
have Neovim >= 0.10, bazelisk, Python 3, stylua, and make on your PATH.

- `make test` — run the test suite headless (clones mini.nvim into `deps/`
  on first run)
- `make fmt` / `make fmt-check` — format / check lua sources
- `tests/fixture/` — a small bazel workspace used as an integration-test bed
- `tests/python_fixture/` — configured Python imports, pip, and generated sources
- With `pyright-langserver` and `basedpyright-langserver` on PATH, `make test`
  also checks real LSP navigation to generated and external imports. Set
  `BZL_TEST_PYRIGHT` / `BZL_TEST_BASEDPYRIGHT` to use specific executables.

## License

[MIT](LICENSE)

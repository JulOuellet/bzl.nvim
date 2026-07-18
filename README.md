# bzl.nvim

[![ci](https://github.com/JulOuellet/bzl.nvim/actions/workflows/ci.yml/badge.svg)](https://github.com/JulOuellet/bzl.nvim/actions/workflows/ci.yml)

Bazel integration for Neovim: browse, run, test, and build bazel targets from a
[snacks.nvim](https://github.com/folke/snacks.nvim) picker, with streaming
output and LSP support for bazel-managed dependencies.


## Features

- Fuzzy picker and collapsible directory tree over all workspace targets
- Filter by testable (`*_test`) or runnable (`*_binary`) rule kinds
- Scope any picker to the current project (nearest `*.bazelproject`
  directory, or the current package)
- Run, test, and build targets; run and test output streams into a
  reusable terminal split
- Test or build a whole subtree from a tree directory (`bazel test //dir/...`)
- Preview a target's BUILD definition while browsing; jump to it directly
- Re-run the last run or test with a single command
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
- [snacks.nvim](https://github.com/folke/snacks.nvim) for the pickers
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
| `:Bzl tree [testable\|runnable] [here]` | Collapsible directory tree of targets |
| `:Bzl sync` | Re-query targets and refresh language server import paths |
| `:Bzl rerun` | Repeat the last run or test |

Arguments can be combined in any order:

- `testable` — only `*_test` targets
- `runnable` — only `*_binary` targets
- `here` — scope to the current project: the nearest directory containing
  a `*.bazelproject` view file, or the current package when none exists.
  Scoped trees open fully expanded.

## Picker keys

| Key | On a target | On a directory (tree only) |
| --- | --- | --- |
| `<CR>` | Test, run, or build, chosen by rule kind | Expand / collapse |
| `<C-t>` | `bazel test` | Test the subtree (`bazel test //dir/...`) |
| `<C-r>` | `bazel run` | — |
| `<C-b>` | `bazel build` (background, notifies result) | Build the subtree |
| `<C-g>` | Jump to the target's BUILD definition | — |

Run and test output streams into a terminal split at the bottom; builds run
in the background and report through `vim.notify`.

No global keymaps are created. Example mappings:

```lua
keys = {
	{ "<leader>bt", function() require("bzl").targets("testable", "here") end, desc = "Bazel Tests (project)" },
	{ "<leader>bT", function() require("bzl").tree("testable") end, desc = "Bazel Tests (workspace)" },
	{ "<leader>br", function() require("bzl").targets("runnable", "here") end, desc = "Bazel Runnables (project)" },
	{ "<leader>bR", function() require("bzl").tree("runnable") end, desc = "Bazel Runnables (workspace)" },
	{ "<leader>bb", function() require("bzl").targets() end, desc = "Bazel All Targets" },
	{ "<leader>bs", function() require("bzl").sync() end, desc = "Bazel Sync" },
},
```

## Supported languages

Browsing, running, testing, and building targets is language-agnostic:
every target `bazel query` returns shows up in the pickers, whatever
language it builds. Language support below refers to `:Bzl sync`
configuring the language server to resolve imports that bazel manages;
Python is the only language wired up so far.

### Python

`:Bzl sync` makes pyright resolve imports that bazel manages, mirroring what
bazel itself puts on `sys.path` at run time:

- pip packages installed by rules_python (discovered under bazel's external
  repositories)
- the workspace root (bazel's default import root)
- first-party import roots declared through the `imports` attribute of
  `py_*` rules

The discovered paths are pushed as `python.analysis.extraPaths` to the
pyright/basedpyright clients attached to the workspace. Sync adds the paths
bazel makes necessary and touches nothing else: all other LSP settings are
preserved.

Supported setups: rules_python with the site-packages repository layout
(bzlmod or WORKSPACE) and pyright or basedpyright. Other setups degrade
gracefully; `:checkhealth bzl` reports what was found.

## Configuration

Defaults:

```lua
require("bzl").setup({
	-- Binary used for all bazel invocations, e.g. "bazelisk" or an absolute path.
	bazel_cmd = "bazel",
	runner = {
		-- Height of the terminal split that shows run/test output.
		height = 15,
	},
})
```

## Health

`:checkhealth bzl` verifies the Neovim version, the bazel binary, and the
snacks.nvim dependency.

## Development

With nix, `nix develop` provides bazel, stylua, and make. Otherwise, have
Neovim >= 0.10, bazelisk, stylua, and make on your PATH.

- `make test` — run the test suite headless (clones mini.nvim into `deps/`
  on first run)
- `make fmt` / `make fmt-check` — format / check lua sources
- `tests/fixture/` — a small bazel workspace used as an integration-test bed

## License

[MIT](LICENSE)

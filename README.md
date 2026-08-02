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
| `:Bzl sync` | Re-query targets and refresh language server import paths |
| `:Bzl rerun` | Repeat the last run or test |

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

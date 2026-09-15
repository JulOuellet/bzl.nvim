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

- Neovim >= 0.11
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
| `:Bzl sync [here\|target patterns…]` | Refresh targets and language metadata; may build generated sources |
| `:Bzl cancel` | Cancel the current workspace's sync |
| `:Bzl status` | Show the latest discovery and application results |

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
configuring a language server from Bazel metadata. The plugin does not install
or start language servers. Configure their roots to the Bazel workspace, then
run `:Bzl sync`. This Neovim command is unrelated to Bazel's `bazel sync` command.

| Language/server | Integration | Status |
| --- | --- | --- |
| Python / Pyright, basedpyright | Configured PyInfo aspect, generated sources, dependency import roots | End-to-end tests in the example |
| C/C++ / clangd | Reads an exported `compile_commands.json`; optional exporter command | Experimental; exporter setup required |
| Go / gopls | Builds rules_go's package driver and configures `gopls.env` | Experimental; real package-driver protocol tested |
| Rust / rust-analyzer | Reads `rust-project.json`; optional rules_rust exporter command | Experimental; exporter tested, LSP acceptance pending |
| Java, Scala, JS/TS, Kotlin | No language-server adapter yet | Picker/run/build/test only |

### Python

The default aspect integration requires **Bazel 8+ and rules_python** in the
workspace's repository mapping. It injects the plugin's `bazel/` repository
without editing your MODULE file. Tested with Bazel 8.7.0, rules_python 1.6.3,
Pyright 1.1.411 and basedpyright 1.39.8 on x86_64 Linux.

Sync builds metadata and Python source output groups, downloading generated
files as needed. It maps configured provider imports to actual source, wheel,
and `bazel-out` locations. It updates `python.analysis.extraPaths` for Pyright
and `basedpyright.analysis.extraPaths` for basedpyright. Existing user paths
and unrelated settings are preserved; obsolete plugin paths are replaced.

Use `:Bzl sync //python:app` to select an environment or `:Bzl sync here` for the
current project. A workspace-wide sync merges paths: it cannot represent
conflicting dependency versions for the same file or enforce strict Bazel deps.
Python interpreter/toolchain selection is not currently synchronized.
`venv_symlinks` providers are explicitly reported as unsupported, not guessed.

`python.mode = "scan"` enables a limited compatibility mode for already
materialized `site-packages` layouts. It is not target-accurate and does not
reliably resolve generated files. `python.materialize = false` in aspect mode
builds metadata only and reports missing sources without applying partial paths.

Project-level `extraPaths` or `executionEnvironments` can override LSP settings;
sync reports these conflicts instead of overwriting your configuration.

### Lifecycle and safety

Sync is explicit, scoped and cancellable. Identical requests coalesce; stale
results cannot replace a newer scope. Each adapter reports its own status, so a
missing exporter does not disable the picker or successful language adapters.
Only clients confined to the selected workspace receive settings. A shared
multi-workspace client is deliberately skipped.

Metadata and the last selected scope are cached under Neovim's cache directory.
On `LspAttach`, the plugin validates build inputs and required files before
reapplying settings, without starting a build. Keep the plugin loaded before
LSP attachment to enable restoration (with lazy.nvim, use `event = "BufReadPre"`
instead of command-only loading if you want restoration before the first command).
BUILD/config writes invalidate the affected workspace. Branch switches and
external edits are detected during validation; run sync explicitly to refresh
an already attached client. Imported bazelrc files, custom extension inputs and
environment-dependent repository changes require `sync.inputs` or a fresh sync.

Only use sync/exporters in trusted workspaces: Bazel repository rules, build
actions and package drivers execute workspace code. The plugin never writes
LSP configuration into your project automatically.

## Configuration

Defaults:

```lua
require("bzl").setup({
	-- Binary used for all bazel invocations, e.g. "bazelisk" or an absolute path.
	bazel_cmd = "bazel",
	startup_args = {}, -- Before the Bazel verb, e.g. --output_base=...
	command_args = { query = {}, info = {}, build = {}, run = {}, test = {} },
	sync = {
		targets = { "//..." },
		inputs = {}, -- Extra workspace-relative/absolute cache inputs
		query_timeout = 120000, -- Milliseconds, applies to query/info
		build_timeout = 0, -- No timeout; :Bzl cancel remains available
		cache = true,
		languages = {
			python = { enabled = true, mode = "aspect", materialize = true },
			cpp = { enabled = true, database = "compile_commands.json", refresh = {} },
			go = { enabled = true, driver_target = "@rules_go//go/tools/gopackagesdriver" },
			rust = { enabled = true, project = "rust-project.json", refresh = {} },
		},
	},
	workspaces = {}, -- Absolute workspace-root keys with configuration overrides
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

For example, with rules_rust 0.65.0, set `rust.refresh` to
`{ "run", "@rules_rust//tools/rust_analyzer:gen_rust_project", "--", "//rust/..." }`.
For C++, configure an upstream exporter such as
[Hedron](https://github.com/hedronvision/bazel-compile-commands-extractor), then
set `cpp.refresh = { "run", "//:refresh_compile_commands" }`.
These are Bazel argument lists, never shell strings. Exporters control their
own scope and internal flags: configure those explicitly; `sync here` does not
rewrite exporter arguments. Exporters may overwrite their generated project files.

clangd databases must use `arguments` arrays. Removing entries previously sent
to clangd requires a server restart. The plugin preserves explicit user compiler
commands and does not enable broad `--query-driver` execution permissions.
The Go launcher currently requires a POSIX shell and preserves startup and
per-command flags; gopls package loading can trigger additional Bazel builds.

## Health

`:checkhealth bzl` verifies prerequisites and reports per-language discovery,
client application counts and configuration conflicts. `ready` means metadata
was discovered, not that a language server is installed or every feature works.

## Development

With nix, `nix develop` provides bazel, stylua, and make. Otherwise, have
Neovim >= 0.11, bazelisk, stylua, and make on your PATH.

- `make test` — run the test suite headless (clones mini.nvim into `deps/`
  on first run)
- `make fmt` / `make fmt-check` — format / check lua sources
- `tests/fixture/` — a small bazel workspace used as an integration-test bed

For manual testing across Python, C++, Go, Rust, and Java, see the standalone
[multilingual playground](examples/multilang/README.md). It includes passing
tests, an intentional failure, and import-resolution checks before and after
sync. Its toolchain downloads and tests are separate from `make test`.

See [integration testing](tests/integration/README.md) for opt-in real-server
checks and the [sync roadmap](docs/sync-plan.md) for remaining milestones.

## License

[MIT](LICENSE)

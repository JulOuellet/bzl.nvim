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
- [pyright](https://github.com/microsoft/pyright) or basedpyright for Python;
  Go and gopls for Go language support

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
| `:Bzl sync` | Refresh targets and configure Python and Go language servers from Bazel |
| `:Bzl sync log` | Reopen the current workspace's latest sync log |

Sync opens a log split at the bottom without moving focus. It streams Bazel's
progress and errors as they arrive, records each sync stage, and shows the current
stage and elapsed time in the window bar, including while Bazel is quiet. The log
follows new output unless you scroll up. Press `q` in the split to close it;
sync continues and `:Bzl sync log` reopens the output. Logs remain available for
the Neovim session, with the next sync replacing that workspace's previous log.

Target picker arguments can be combined in any order:

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
configuring language servers to resolve imports that Bazel manages. Sync detects
Python and Go rules and prepares each language in turn. In a mixed workspace,
one language's failure preserves its previous configuration while successful
languages update. Disable a language with `python.enabled = false` or
`go.enabled = false` to leave its servers alone on subsequent syncs.

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

### Go

`:Bzl sync` prepares the workspace's
[rules_go package driver](https://github.com/bazel-contrib/rules_go/blob/master/docs/editors.md)
and configures gopls through `gopls.env.GOPACKAGESDRIVER`. The driver supplies
Bazel's package graph, including dependencies selected by build flags and
generated Go sources. Packages are loaded and built as gopls requests them;
sync first builds the driver and validates it by loading standard-library
metadata. A successful sync means the driver is ready, while gopls can continue
loading project packages in the background.

Install Go and gopls. **Configure gopls to use the Bazel workspace root** (the
directory containing `MODULE.bazel`, `WORKSPACE.bazel`, or `WORKSPACE`). The default
nvim-lspconfig root detection looks for Go module/workspace files and `.git`, so a
Bazel workspace nested inside a Git repository can get the wrong root. bzl.nvim
only applies the package driver to clients belonging to that Bazel workspace;
sync does not change a running client's root.

With Neovim 0.11+ and nvim-lspconfig, configure the root before enabling gopls:

```lua
local default_root_dir = vim.lsp.config.gopls.root_dir
vim.lsp.config("gopls", {
  root_dir = function(bufnr, on_dir)
    local root = vim.fs.root(bufnr, { "MODULE.bazel", "WORKSPACE.bazel", "WORKSPACE" })
    if root then
      on_dir(root)
    else
      default_root_dir(bufnr, on_dir)
    end
  end,
})
vim.lsp.enable("gopls")
```

If you use the older `require("lspconfig").gopls.setup({...})` API, add `root_dir`
to your existing setup, keeping your capabilities and settings:

```lua
require("lspconfig").gopls.setup({
  -- Keep your existing options here.
  root_dir = function(fname)
    return vim.fs.root(fname, { "MODULE.bazel", "WORKSPACE.bazel", "WORKSPACE" })
      or require("lspconfig.util").root_pattern("go.work", "go.mod", ".git")(fname)
  end,
})
```

After changing the root configuration, restart Neovim and run `:Bzl sync` again.
If imports remain underlined, open `:Bzl sync log`. A line such as
`go: package driver ready -> 0 clients` means the driver was prepared but no gopls
client received it. If gopls is attached, check its root with `:LspInfo`: it should
be the Bazel workspace directory, not a parent Git repository. Zero clients is
also expected when gopls has not started yet; the saved driver is applied when a
matching client attaches.

Sync probes `@rules_go` and `@io_bazel_rules_go` to find the driver, supporting
both common Bzlmod and WORKSPACE repository names. Override the driver's label
when your repository uses a different name, for example:

```lua
require("bzl").setup({
  go = { driver_target = "@my_rules_go//go/tools/gopackagesdriver" },
  build_flags = { "--config=dev" },
})
```

The driver uses the plugin's `bazel_cmd`, `startup_flags`, and `build_flags`,
including during subsequent gopls requests. Go package loading follows gopls'
requests; `python.targets` only scopes Python. Sync also adds Bazel build-file
patterns to `gopls.workspaceFiles` so edits trigger package reloads. Existing
gopls settings and explicitly configured package drivers (including `off`) are
preserved. Clear your explicit `GOPACKAGESDRIVER` to let the plugin manage it.

Repeated syncs refresh an already-running gopls, and its configuration is
reapplied when the server restarts. Sync can also prepare the driver before gopls
starts, including clients using a custom executable outside PATH. Set `go = false`
if you do not use Go language support. Launchers live in Neovim's temporary directory
and last for the editor session. Sync does not create a `go.mod` or edit the
workspace. A failed driver preparation retains the previous configuration;
package-loading errors after configuration are reported by gopls.

Go sync requires a POSIX shell and is tested with Bazel 8.7.0, rules_go 0.58.3,
the Go 1.25.5 Bazel SDK, and gopls 0.22.0. The initial integration covers native
Go libraries, binaries, and tests on Linux; cgo and cross-compilation are not
validated. gopls' Bazel integration depends on rules_go's driver rather than
gopls' native Go module support. Use an output base without spaces: the tested
Gazelle dependency fails to build its tools when that path contains spaces.

## Configuration

Defaults:

```lua
require("bzl").setup({
	-- Binary used for all bazel invocations, e.g. "bazelisk" or an absolute path.
	bazel_cmd = "bazel",
	startup_flags = {}, -- before the Bazel subcommand, e.g. --output_base=...
	build_flags = {}, -- used by build/run/test, cquery, and info
	python = {
		enabled = true,
		targets = {}, -- empty selects all workspace py_* rules
	},
	go = {
		enabled = true,
		driver_target = nil, -- auto-detect @rules_go or @io_bazel_rules_go
	},
	picker = {
		-- Show the BUILD-file preview panel when the picker opens.
		preview = false,
	},
	sync = {
		-- Height of the split that shows sync progress and logs.
		height = 15,
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
snacks.nvim dependency, and reports the last successful sync for each language in the
current workspace.

## Development

With nix, `nix develop` provides Bazel, Python 3, Go, gopls, stylua, and make.
Otherwise, have Neovim >= 0.10, bazelisk, Python 3, stylua, and make on your PATH.

- `make test` — run the test suite headless (clones mini.nvim into `deps/`
  on first run)
- `make fmt` / `make fmt-check` — format / check lua sources
- `tests/fixture/` — a small bazel workspace used as an integration-test bed
- `tests/python_fixture/` — configured Python imports, pip, and generated sources
- `tests/go_fixture/` — Bazel-only Go imports, generated sources, and configuration changes
- With `pyright-langserver` and `basedpyright-langserver` on PATH, `make test`
  also checks real LSP navigation to generated and external imports. Set
  `BZL_TEST_PYRIGHT` / `BZL_TEST_BASEDPYRIGHT` to use specific executables.
- With Go and gopls on PATH, `make test` checks actual Go navigation, diagnostics,
  repeated syncs, failure recovery, and server restarts. `BZL_TEST_GOPLS` selects
  a specific server executable. CI installs all three language servers.

Sync adapters are internal modules under `lua/bzl/languages/`, implementing
`detect(context)`, `prepare(context, done)`, and `apply(client, root, model)`.
The coordinator owns discovery, configuration snapshots, invalidation, and
publication. Each adapter owns its model and server settings; a model supplies
a `summary` for status and health output. Models are kept in memory per workspace
and language and published only after preparation and configuration validation.

## License

[MIT](LICENSE)

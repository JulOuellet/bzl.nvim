# Multilingual Bazel playground

A standalone, nested Bazel workspace for manually exercising bzl.nvim and for
future language-server integration tests. It can be copied outside the plugin
repository. It does not change `tests/fixture/` or the default plugin test suite.

Five languages each have a library, executable, and test. Python additionally
has a pinned PyPI dependency, generated code, and an intentional failing test.
The examples use small greeting functions so you can focus on build/editor
integration rather than application behavior.

## Start here

On Linux/macOS, install Bazel 8.7.0 (or Bazelisk, which reads `.bazelversion`) and
a working C/C++ compiler. Bazel downloads the pinned Python, Go, Rust, and Java
toolchains and dependencies on first use. Expect the first build to take several
minutes and use substantial disk space. Internet access is required initially.

```sh
cd examples/multilang
make query
make test
make run
```

`make test` should pass six tests. `make run` runs six binaries. The Python app
prints `Hello, Bazel! (v1.2.0)`, the generated app prints
`Hello from generated Python!`, and the other apps print `Hello, Bazel!`.

On **NixOS**, use this workspace's shell first:

```sh
cd examples/multilang
nix develop path:.
make test
```

For a single noninteractive command, use `nix run path:. -- make test` (or
`nix run path:. -- make run`). This enters the same FHS environment.

The Linux shell supplies an FHS environment so downloaded toolchains can use
the conventional dynamic linker and libraries they expect. The plugin root's
ordinary `nix develop` shell does not provide this environment. Open Neovim from
inside this shell too, so picker actions inherit the same working environment.
The Nix shell supplies Neovim but does not install language servers or plugins;
use your existing editor setup. Nix's `path:.` form includes newly created files
before they have been added to Git.

You can test one language without building all of them:

```sh
bazel test //python/...
bazel test //cpp/...
bazel test //go/...
bazel test //rust/...
bazel test //java/...
```

## Picker and runner checks

Open a source file with your existing bzl.nvim and snacks.nvim configuration:

```sh
nvim python/main.py
```

1. Run `:Bzl targets`. Expect targets from all five languages.
2. Run `:Bzl targets runnable`. Select `//python:app` and press Enter. Expect
   the versioned greeting in the terminal split. Repeat with each language.
3. Run `:Bzl targets testable`. Select a passing test, then explicitly run
   `//python:failing_test`. Expect the intentional failure message and nonzero
   exit status in the terminal. The failing test has `tags = ["manual"]`, so
   `bazel test //...` does not run it.
4. Toggle the BUILD preview with `<A-p>` and jump with `<C-g>`.
5. From a Python source file, `:Bzl targets here` should include only Python
   targets. `python/python.bazelproject` supplies the directory boundary; the
   current plugin uses its location, not its `targets:` contents.
6. Save a BUILD file and reopen the picker to check cache invalidation.
7. Open the plugin's original `tests/fixture/BUILD.bazel` in another buffer and
   switch between workspaces. Each picker/action should retain its own root.

## Import and language-server checks

Bazel passing is one assertion; the editor understanding Bazel is another.
Start with a fresh Neovim session, and use `:checkhealth vim.lsp` to confirm that
the relevant server is attached. No diagnostics from an unattached server is
not a successful integration test.

The root `pyproject.toml` lets Pyright/basedpyright identify this workspace. It
does not preconfigure import paths. For other servers, configure their root to
this `MODULE.bazel` workspace as needed. There is deliberately no `go.mod`,
`Cargo.toml`, Maven project, or manually maintained compilation database to hide
the missing Bazel integration.

| Open this file | What it exercises | Expected behavior with the current plugin |
| --- | --- | --- |
| `python/main.py` | `acme.greeting`, exposed by `imports = ["src"]` | Pyright should resolve it after `:Bzl sync` |
| `python/src/acme/greeting.py` | `packaging.version`, installed by rules_python | Sync materializes the wheel and supplies its import root |
| `python/generated_main.py` | `build_info.py`, generated under `bazel-bin` | Sync materializes the source and supplies its output root |
| `python/diagnostics/type_error.py` | A real type error: `greet(123)` | Once imports resolve, the argument-type error should remain |
| `cpp/main.cc` | A Bazel virtual include path, `multilang/greeting.h` | Configure a compilation database exporter; sync reads its output for clangd |
| `go/main.go` | A local dependency declared by its Bazel import path | Sync builds/configures rules_go's package driver for gopls; experimental |
| `rust/main.rs` | A dependency crate declared only in BUILD | Configure the rules_rust exporter below; sync loads the crate graph; experimental |
| `java/src/demo/Main.java` | Sources split across Bazel targets | Needs a Java project model for dependable support; same-directory resolution alone is not proof of Bazel integration |

Both **Pyright** and **basedpyright** use their own settings namespace.
Existing user configuration can already resolve some imports, so the exact
initial diagnostics will vary.

For each language, record the server name/version, ruleset version, source file,
diagnostic text, and whether go-to-definition reaches the expected dependency.
Check completion and hover as well as disappearance of an underline.

### Why sync changes the red underlines

Bazel and the language server are separate programs. Bazel knows the dependency
graph and prepares the runtime/compile environment. A language server normally
looks at the source tree and its own configured environment. It does not
automatically inherit the environment of `bazel run`.

For `acme.greeting`, the editor needs `python/src` as a search root. For
`packaging.version`, it needs the downloaded wheel's `site-packages` directory.
For `build_info`, it needs a generated file to exist and the matching output
directory in its search roots. Listing a target alone guarantees none of these.

`:Bzl sync` now queries targets, extracts configured Python provider metadata,
materializes generated sources, and updates eligible clients' import paths.
It caches metadata for validated restoration on later LSP attachment, including
editor restarts. It does not install a language server or suppress diagnostics.
Use `:Bzl sync //python/...` for a Python-only scope. Whole-workspace sync also
runs the Go adapter and reports missing C++/Rust exporters separately.

For the pinned Rust ruleset, configure this adapter before syncing:

```lua
require("bzl").setup({
  sync = { languages = { rust = {
    refresh = { "run", "@rules_rust//tools/rust_analyzer:gen_rust_project", "--", "//rust/..." },
  } } },
})
```

This writes the ignored `rust-project.json`. For C++, add an exporter such as
Hedron to a copy of this workspace and configure `cpp.refresh` accordingly;
the example deliberately does not pin an untested compilation exporter.

## Scope and follow-up

Validated on x86_64 NixOS with the included shell and Bazel 8.7.0: all six
passing tests, all six runnable binaries, the intentional failure, and the
plugin's discovery of all 21 targets/BUILD locations and four Python search
paths. Automated Pyright/basedpyright checks verify diagnostics, definitions,
hover and cache restoration; the Go test exercises the package-driver protocol.
The Rust exporter has been run successfully. C++/Go/Rust LSP behavior and the
Snacks UI remain manual checks; other platforms have not been exercised here.

See [opt-in integration tests](../../tests/integration/README.md). JS/TS, Scala,
and Kotlin can be added once their adapters have
a specific server/tooling combination to verify. Python 1.x is pinned to test
the current plugin's `site-packages` discovery; it is not a claim of support for
all newer rules_python layouts.

See [the sync roadmap](../../docs/sync-plan.md) for remaining acceptance criteria.

References:

- [Pyright import resolution](https://github.com/microsoft/pyright/blob/main/docs/import-resolution.md)
- [Bazel aspects](https://bazel.build/extending/aspects)
- [C/C++ compilation database extraction](https://github.com/hedronvision/bazel-compile-commands-extractor)
- [rules_go editor setup](https://github.com/bazel-contrib/rules_go/wiki/Editor-setup)
- [rules_rust rust-analyzer integration](https://bazelbuild.github.io/rules_rust/rust_analyzer.html)

Upstream integration commands can change: consult documentation for the pinned
ruleset version before applying commands from a latest-version guide.

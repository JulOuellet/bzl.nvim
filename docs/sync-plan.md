# Proposed redesign of :Bzl sync

Status: initial implementation landed in the working tree. The coordinator,
Python aspect/settings, validated cache restoration and initial C++/Go/Rust
adapters are implemented. Python has real Pyright/basedpyright acceptance tests;
Go has a real package-driver test. C++/Rust language-server acceptance, Python
runtime metadata, conflicting-environment fixtures, rules_python 2.x/venv
support, and Java/Scala/JS/TS/Kotlin remain follow-up work. The sections below
retain the broader design and acceptance roadmap, not a claim that every item
has shipped. `:Bzl sync` is a Neovim command; it is not Bazel's own
`bazel sync` repository command and is not a Bazel target.

## Outcome

After sync, the relevant language servers should understand the selected Bazel
project's sources, dependencies, generated files, and toolchain settings as far
as their supported integration permits. Preserve genuine diagnostics and user
configuration. Keep target browsing/build/run/test usable without any language
server or language integration installed.

Support is defined per **language server + Bazel ruleset/version + platform**.
A target appearing in the picker is not evidence of language intelligence.

## 1. Establish a safe sync coordinator

Introduce `lua/bzl/sync.lua`; keep `init.lua` as command/API dispatch. Capture a
context before any async work: normalized workspace root, originating buffer,
selected target scope, Bazel executable, startup arguments, command arguments,
and platform/configuration. Query/build/metadata extraction must share the
configuration where applicable. Changing it invalidates derived metadata.

Use per-context generations and pending-job state. Coalesce identical requests;
cancel or supersede obsolete requests; reject stale callbacks before publishing
cache entries or touching clients. A BUILD write marks the affected workspace
dirty. Do not overwrite a newer result or clear other workspaces' state.

Extend `cli.run` to return a cancellable process handle and deliver one structured
completion on success, spawn failure, nonzero exit, cancellation, or timeout.
Differentiate startup flags from command flags; continue using argument arrays.
Background queries and builds need independent, appropriate timeout policies.

Acceptance: deterministic tests for overlapping syncs, late results after
invalidation, configuration changes, cancellation, and switching buffers or
workspaces mid-sync. Align README/health/CI on Neovim >= 0.11 before using its
client method API consistently.

## 2. Introduce a small adapter contract

Replace unconditional `python.sync()` with registered adapters under
`lua/bzl/languages/`. Each adapter should provide:

- `detect(context)`: whether the workspace and configured tooling are supported;
  do not rely solely on filename extensions or rule-name suffixes.
- `discover(context, callback)`: asynchronously obtain metadata, with cancellation
  propagated through the coordinator.
- `apply(context, metadata, client)`: apply only to an eligible client, using
  server-specific configuration or reload mechanisms.
- `health(context)`: show tooling requirements, last successful discovery, and
  known limitations without triggering a build.

Return a structured result including status (`ready`, `partial`, `unsupported`,
`failed`, `cancelled`), diagnostics, generated artifacts, and applied client IDs.
Do not require every adapter to produce a generic list of import paths: compiler
commands, package drivers, and project graphs carry different information.

Allow explicit enable/disable and per-workspace adapter configuration. Run only
relevant adapters. Coordinate Bazel operations per workspace to avoid launching
several builds that simply wait for the same Bazel server lock. One adapter's
failure must not discard successful target discovery or another adapter's result.

## 3. Correct Python's existing behavior first

Implement server-specific settings for Pyright and basedpyright. Keep a baseline
of user-owned paths and track the contribution owned by bzl.nvim separately.
Replace obsolete plugin paths while retaining current user paths; deduplicate
without destroying search order. Detect project configuration that overrides
extraPaths and explain it rather than claiming successful application.

Match clients through their workspace roots/folders and attached file buffers.
A rootless client is not automatically eligible. If a shared client cannot
represent different workspace settings safely, report the limitation instead of
applying global paths to unrelated files.

Initially keep directory scanning as an explicitly limited compatibility mode
for tested rules_python layouts. Preserve the last good discovery on failure;
report missing wheel materialization, unsupported layouts, and partial results.

Acceptance: real Pyright resolves `acme.greeting` and `packaging.version` in the
example and navigates to their actual files; `greet(123)` still produces a type
diagnostic. Repeat with basedpyright and preexisting extraPaths. A failed sync
must not remove previously working user or Bazel paths.

## 4. Add reliable Python build metadata

Prototype a small Bazel aspect for selected targets. Collect configured Python
provider information, transitive sources/imports, generated artifacts, and the
runtime information needed by the adapter. Map runfiles/repository paths to
actual local source and output locations; do not blindly prepend the workspace
root. Version the exported metadata format.

Decide aspect distribution explicitly: a documented companion Bazel module or
an injected repository, with versioned rules_python compatibility. This is a
real project integration prerequisite, not a hidden assumption about users'
MODULE files. Reuse existing exporters when they meet the requirements.

Build only required metadata/generated-source output groups where possible.
Make this work and its scope visible in sync progress; offer a metadata-only
mode that reports missing outputs rather than a false success. Remote builds
also require relevant generated artifacts to be downloaded locally.

Python servers may not represent two conflicting target environments for the
same file. Define a selected-target/project policy and report ambiguity. Never
claim strict Bazel dependency enforcement merely because an import resolves.

Acceptance: `python/generated_main.py` resolves after generated outputs are
materialized and applied. Add a subsequent fixture with unrelated versions of
one dependency to verify the chosen scope, plus a custom Python rule exposing
PyInfo to avoid relying on `py_*` names. Test supported 1.x and 2.x rules_python
layouts separately rather than inferring compatibility from one pin.

## 5. Make settings survive the editor lifecycle

Cache validated metadata per workspace, scope, configuration, and adapter
version. Use Neovim's cache directory with atomic writes; never serialize live
clients, callbacks, arbitrary code, or environment secrets. Stored paths need
existence/freshness checks because Bazel output bases can change or be cleaned.

Apply appropriate settings before server initialization when required, and on
`LspAttach` when dynamic configuration is supported. Some adapters change a
server command/environment and require an explicit restart; do not assume
`workspace/didChangeConfiguration` works for all of them. Reapply on server
restart and keep user configuration ownership clear.

Start with explicit sync plus fast reuse of valid cached state. Add optional
debounced auto-sync later. Detect external build-file changes via validation or
a documented refresh path; BufWritePost alone cannot cover branch switches and
edits from other programs.

Acceptance: sync before attachment, server restart, editor restart, deleted
outputs, and two simultaneous workspaces. Stale cached data must be visible as
stale and refreshed; it must not silently become authoritative.

## 6. Add languages through upstream tooling

| Adapter | Integration | Initial acceptance |
| --- | --- | --- |
| C/C++ / clangd | Existing Bazel compilation-database exporter, selected targets/flags, generated headers | `multilang/greeting.h` resolves and definition reaches the real source header |
| Go / gopls | rules_go package driver and toolchain-aware settings | `example.com/bzl-multilang/greeting` resolves without a shadow go.mod |
| Rust / rust-analyzer | The pinned rules_rust exporter/launcher and crate graph, including sysroot/proc macros when present | The local `greeting` crate resolves without Cargo.toml |
| Scala / Metals | Existing Bazel BSP import/reload workflow | Add a Scala fixture and verify dependency navigation through Metals |
| Java / selected server | Evaluate BSP or a supported project exporter, preserving classpaths, JDKs, generated sources | Extend the Java fixture with external jars and generated classes before claiming full support |

JS/TS and Kotlin follow separate capability investigations. BSP describes build
information; Neovim's LSP client cannot directly use a BSP server as a language
server. Prefer a language server with a supported bridge rather than implementing
a general IDE project model in Lua.

## 7. Verification and rollout

Keep existing small tests fast. Add an opt-in integration job for the example,
then real-language-server jobs with pinned binaries and clean configurations.
Use protocol responses for diagnostics, hover, completion, and definitions;
wait for observable server state with timeouts rather than fixed sleeps.
Verify meaningful diagnostic codes and destination paths, not screenshot colors.

Roll out as separate reviewable changes: coordinator/cache correctness; adapter
contract and Python settings; metadata extraction/generated Python; persistence
and attachment lifecycle; C/C++; Go; Rust; later language integrations. Document
current support and partial failures in `:checkhealth bzl` and native help.

The first usable milestone is correct, isolated Python settings and clear sync
status. The first milestone matching IntelliJ-style generated-import behavior
also requires metadata extraction and artifact materialization.

## Upstream references

- [Bazel aspects and IDE information extraction](https://bazel.build/extending/aspects)
- [IntelliJ Python metadata collection](https://github.com/bazelbuild/intellij/blob/master/aspect/intellij_info_impl.bzl)
- [Pyright import resolution](https://github.com/microsoft/pyright/blob/main/docs/import-resolution.md)
- [basedpyright settings](https://docs.basedpyright.com/latest/configuration/language-server-settings/)
- [Neovim LSP lifecycle](https://neovim.io/doc/user/lsp/)
- [Hedron compilation database exporter](https://github.com/hedronvision/bazel-compile-commands-extractor)
- [rules_go editor integration](https://github.com/bazel-contrib/rules_go/wiki/Editor-setup)
- [rules_rust integration](https://bazelbuild.github.io/rules_rust/rust_analyzer.html)
- [Metals Bazel integration](https://scalameta.org/metals/docs/build-tools/bazel/)

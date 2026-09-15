"""Export configured Python imports and sources for bzl.nvim (schema version 1)."""

load("@rules_python//python:py_info.bzl", "PyInfo")

def _python_impl(target, ctx):
    if PyInfo not in target:
        return []
    info = target[PyInfo]
    sources = depset(transitive = [
        getattr(info, "transitive_original_sources", info.transitive_sources),
        getattr(info, "transitive_pyi_files", depset()),
    ])
    output = ctx.actions.declare_file(ctx.label.name + ".bzl-python.json")
    ctx.actions.write(output, json.encode({
        "version": 1,
        "label": str(ctx.label),
        "workspace": ctx.workspace_name,
        "imports": info.imports.to_list(),
        "sources": [{"path": f.path, "short_path": f.short_path, "source": f.is_source} for f in sources.to_list()],
        "venv": bool(getattr(info, "venv_symlinks", depset()).to_list()),
    }))
    return [OutputGroupInfo(bzl_python = depset([output]), bzl_python_sources = sources)]

python = aspect(implementation = _python_impl)

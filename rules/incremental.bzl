def _drop_ext(path):
    return path[:path.rfind(".")]

def _swift_library_impl(ctx):
    module = ctx.outputs.module
    module_name = ctx.label.name
    library = ctx.outputs.library

    dependencies = [dep[DefaultInfo].files for dep in ctx.attr.deps]
    swiftmodule_dependencies = [
        f
        for dependency_set in dependencies
        for f in dependency_set.to_list()
        if f.extension == "swiftmodule"
    ]

    compile_args = [
        "-incremental",
        "-v", "-driver-show-incremental",
        "-enable-batch-mode",
        "-module-name", module_name,
        "-I", module.dirname,
    ]
    compile_args += [f.path for f in ctx.files.srcs]

    object_paths = []
    output_file_map = {}
    for source in ctx.files.srcs:
        # Ideally path/to/File.swift would be output to bindir/path/to/File.o. Like this:
        # object_path = bindir + _drop_ext(source.path) + ".o"
        # However the intermediate paths don't exist, it requires a `mkdir -p`.
        # Instead, the output path is bindir/<module_name>_File.o
        prefix = ctx.var["BINDIR"] + "/" + module_name + "_" + _drop_ext(source.basename)
        object_path = object + ".o"
        object_paths.append(object_path)
        output_file_map[source.path] = {
            "object": object_path,
            "swiftmodule": prefix + ".swiftmodule",
            "swift-dependencies": prefix + ".swiftdeps",
        }

    # Empty string key tells swiftc the path to write module incremental state.
    output_file_map[""] = {
        "swift-dependencies": _drop_ext(module.path) + ".swiftdeps",
    }

    outputs_json = ctx.actions.declare_file("modules/{}.outputs.json".format(module_name))
    ctx.actions.write(
        outputs_json,
        struct(**output_file_map).to_json(),
    )

    ctx.actions.run(
        mnemonic = "CompileSwift",
        executable = "swiftc",
        arguments = compile_args + [
            "-output-file-map", outputs_json.path,
            "-emit-library", "-o", library.path,
            "-emit-module-path", module.path,
        ],
        inputs = ctx.files.srcs + swiftmodule_dependencies + [outputs_json],
        outputs = [module, library],
    )

    return [
        DefaultInfo(files = depset([module, library], transitive = dependencies)),
    ]


swift_library = rule(
    implementation = _swift_library_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = [".swift"]),
        "deps": attr.label_list(),
    },
    outputs = {
        "module": "modules/%{name}.swiftmodule",
        "library": "modules/lib%{name}.dylib",
    }
)

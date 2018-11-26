def _drop_ext(path):
    return path[:path.rfind(".")]

def _swift_library_impl(ctx):
    module = ctx.outputs.module
    module_name = ctx.label.name
    library = ctx.outputs.library

    dependencies = [dep[DefaultInfo].files for dep in ctx.attr.deps]
    transitive_files = depset(transitive = dependencies).to_list()

    compile_args = [
        "-incremental",
        "-driver-show-incremental",
        "-enable-batch-mode",
        "-module-name", module_name,
    ]

    # Search paths for .swiftmodule files.
    compile_args += [
        option
        for f in transitive_files
        if f.extension == "swiftmodule"
        for option in ("-I", f.dirname)
    ]

    # Pass the dylib paths through to the linker.
    compile_args += [
        option
        for f in transitive_files
        if f.extension == "dylib"
        for option in ("-Xlinker", f.path)
    ]

    # After all that, add the module's Swift source files as args.
    compile_args += [f.path for f in ctx.files.srcs]

    bindir = ctx.var["BINDIR"]
    object_paths = []
    output_file_map = {}
    for source in ctx.files.srcs:
        # Ideally path/to/File.swift would be output to bindir/path/to/File.o. Like this:
        # object_path = bindir + _drop_ext(source.path) + ".o"
        # However the intermediate paths don't exist, it requires a `mkdir -p`.
        # Instead, the output path is bindir/<module_name>_File.o
        prefix = "{}/{}_{}".format(bindir, module_name, _drop_ext(source.basename))
        object_path = prefix + ".o"
        object_paths.append(object_path)
        output_file_map[source.path] = {
            "object": object_path,
            "swiftmodule": prefix + ".swiftmodule",
            "swift-dependencies": prefix + ".swiftdeps",
        }

    # Empty string key tells swiftc the path to write module incremental state.
    output_file_map[""] = {
        "swift-dependencies": "{}/{}.swiftdeps".format(bindir, module_name),
    }

    outputs_json = ctx.actions.declare_file("{}.outputs.json".format(module_name))
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
        inputs = ctx.files.srcs + transitive_files + [outputs_json],
        outputs = [module, library],
    )

    return [
        DefaultInfo(
            files = depset(direct = [module, library], transitive = dependencies)
        ),
    ]


swift_library = rule(
    implementation = _swift_library_impl,
    attrs = {
        "srcs": attr.label_list(allow_files = [".swift"]),
        "deps": attr.label_list(),
    },
    outputs = {
        "module": "%{name}.swiftmodule",
        "library": "lib%{name}.dylib",
    }
)

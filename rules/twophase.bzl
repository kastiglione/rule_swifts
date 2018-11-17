def _swift_library_impl(ctx):
    module = ctx.outputs.module
    library = ctx.outputs.library
    module_name = ctx.label.name

    dependencies = [dep[DefaultInfo].files for dep in ctx.attr.deps]
    swiftmodule_dependencies = [
        f
        for dependency_set in dependencies
        for f in dependency_set.to_list()
        if f.extension == "swiftmodule"
    ]

    compile_args = [
        "-O", "-whole-module-optimization",
        "-module-name", module_name,
        "-I", module.dirname,
    ]
    compile_args += [f.path for f in ctx.files.srcs]

    ctx.actions.run(
        mnemonic = "CompileSwiftModule",
        executable = "swiftc",
        arguments = compile_args + [
            "-emit-module-path", module.path
        ],
        inputs = ctx.files.srcs + swiftmodule_dependencies,
        outputs = [module],
    )

    ctx.actions.run(
        mnemonic = "CompileSwift",
        executable = "swiftc",
        arguments = compile_args + [
            "-emit-library", "-o", library.path,
        ],
        inputs = ctx.files.srcs + swiftmodule_dependencies,
        outputs = [library],
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

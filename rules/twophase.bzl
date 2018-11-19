def _swift_library_impl(ctx):
    module = ctx.outputs.module
    library = ctx.outputs.library
    module_name = ctx.label.name

    dependencies = [dep[DefaultInfo].files for dep in ctx.attr.deps]
    transitive_files = depset(transitive = dependencies).to_list()
    swiftmodule_files = [f for f in transitive_files if f.extension == "swiftmodule"]

    compile_args = [
        "-O", "-whole-module-optimization",
        "-module-name", module_name,
    ]
    compile_args += ["-I" + f.dirname for f in swiftmodule_files]
    compile_args += [f.path for f in ctx.files.srcs]

    ctx.actions.run(
        mnemonic = "CompileSwiftModule",
        executable = "swiftc",
        arguments = compile_args + [
            "-emit-module-path", module.path
        ],
        inputs = ctx.files.srcs + swiftmodule_files,
        outputs = [module],
    )

    ctx.actions.run(
        mnemonic = "CompileSwift",
        executable = "swiftc",
        arguments = compile_args + [
            "-emit-library", "-o", library.path,
        ],
        inputs = ctx.files.srcs + swiftmodule_files,
        outputs = [library],
    )

    return [
        DefaultInfo(
            files = depset(direct = [module, library], transitive = dependencies),
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

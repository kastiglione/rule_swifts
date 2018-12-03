load("@build_bazel_rules_swift//swift:swift.bzl", "SwiftInfo")

def _drop_ext(path):
    "Return the path with no extension."
    return path[:path.rfind(".")]

def _list_get(values, key):
    "Find the value that follows the key, if any."
    count = len(values)
    if count == 0:
        return None
    for i in range(count - 1):
        if values[i] == key:
            return values[i + 1]
    return None

def _compile_target(ctx):
    cpu = ctx.fragments.apple.single_arch_cpu
    platform = ctx.fragments.apple.single_arch_platform
    xcode_config = ctx.attr._xcode_config[apple_common.XcodeVersionConfig]
    version = xcode_config.minimum_os_for_platform_type(platform.platform_type)
    return "{}-apple-{}{}".format(cpu, platform.platform_type, version)

def _swift_library_impl(ctx):
    module_name = ctx.attr.module_name or ctx.label.name
    module = ctx.outputs.module
    library = ctx.outputs.library

    bindir = ctx.var["BINDIR"]

    # Begin -output-file-map handling code.
    # This is what makes incremental work.
    output_file_map = {}
    for source in ctx.files.srcs:
        # These are incremental artifacts that need to persist between builds, and as
        # such are not declared to Bazel. If they were declared, Bazel would remove them.
        prefix = "{}/{}".format(bindir, _drop_ext(source.path))
        output_file_map[source.path] = {
            "object": prefix + ".o",
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

    # End -output-file-map handling code.

    compile_args = [
        "-target", _compile_target(ctx),
        "-incremental",
        "-driver-show-incremental",
        "-enable-batch-mode",
        "-module-name", module_name,
        "-emit-object",
        "-emit-module-path", module.path,
        "-output-file-map", outputs_json.path,
    ]

    swift_dependencies = depset(transitive = [
        dep[SwiftInfo].transitive_swiftmodules
        for dep in ctx.attr.deps
    ]).to_list()

    # Search paths for .swiftmodule files.
    compile_args += ["-I" + f.dirname for f in swift_dependencies]

    # Add the source files as args.
    compile_args += [f.path for f in ctx.files.srcs]

    ctx.actions.run(
        mnemonic = "CompileSwift",
        executable = ctx.executable._swiftc,
        arguments = compile_args,
        inputs = ctx.files.srcs + swift_dependencies + [outputs_json],
        outputs = [module, library],
    )

    return [SwiftInfo(
        module_name = module_name,
        swift_version = _list_get(ctx.fragments.swift.copts(), "-swift-version"),
        direct_swiftmodules = [module],
        direct_libraries = [library],
        transitive_swiftmodules = depset([module], transitive = [
            dep[SwiftInfo].transitive_swiftmodules
            for dep in ctx.attr.deps
        ]),
        transitive_libraries = depset([library], transitive = [
            dep[SwiftInfo].transitive_libraries
            for dep in ctx.attr.deps
        ]),
        transitive_defines = depset([]),
        transitive_additional_inputs = depset([]),
        transitive_linkopts = depset([]),
    )]

swift_library = rule(
    implementation = _swift_library_impl,
    fragments = ["apple", "swift"],
    attrs = {
        "module_name": attr.string(),
        "srcs": attr.label_list(allow_files = [".swift"]),
        "deps": attr.label_list(providers = [[SwiftInfo]]),
        "_xcode_config": attr.label(default = configuration_field(
            fragment = "apple",
            name = "xcode_config_label",
        )),
        "_swiftc": attr.label(
            default = "//tools:swiftc",
            executable = True,
            cfg = "host",
        ),
    },
    outputs = {
        "module": "%{name}.swiftmodule",
        "library": "lib%{name}.a",
    },
)

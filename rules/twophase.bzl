load("@build_bazel_rules_swift//swift:swift.bzl", "SwiftInfo", "SwiftClangModuleInfo")

def _list_get(key, values):
    "Find the value that follows the key, if any."
    for i in range(len(values)):
        if values[i] == key:
            return values[i + 1]
    return None

def _bazel_target(ctx):
    cpu = ctx.fragments.apple.single_arch_cpu
    platform = ctx.fragments.apple.single_arch_platform
    platform_type = platform.platform_type
    version_config = ctx.attr._xcode_config[apple_common.XcodeVersionConfig]
    version = version_config.minimum_os_for_platform_type(platform_type)
    triple = "{}-apple-{}{}".format(cpu, platform_type, version)
    if not platform.is_device:
        triple += "-simulator"
    return triple

def _file_dirname(file):
    return file.dirname

def _string_dirname(path):
    return path[:path.rfind("/")]

def _swift_library_impl(ctx):
    module = ctx.outputs.module
    module_name = ctx.attr.module_name # or ctx.label.name
    deps = ctx.attr.deps

    swift_deps = [dep[SwiftInfo] for dep in deps if SwiftInfo in dep]
    swiftmodules = [
        dep.transitive_swiftmodules
        for dep in swift_deps
    ]

    objc_deps = [dep[apple_common.Objc] for dep in deps if apple_common.Objc in dep]
    frameworks = [
        dep.static_framework_file
        for dep in objc_deps
    ]

    sdk = ctx.fragments.apple.single_arch_platform.name_in_plist.lower()
    target = _bazel_target(ctx)

    compile_args = ctx.actions.args()
    compile_args.add_all(["-sdk", sdk])
    compile_args.add_all(["swiftc", "-target", target])
    compile_args.add_all(["-module-name", module_name])
    # Use --swiftcopt=-O if desired.
    compile_args.add_all(["-whole-module-optimization"])
    compile_args.add("-parse-as-library")

    compile_args.add_all(
        depset(transitive = swiftmodules),
        format_each = "-I%s",
        map_each = _file_dirname
    )

    compile_args.add_all(
        depset(transitive = [dep.framework_dir for dep in objc_deps]),
        format_each = "-F%s",
        map_each = _string_dirname,
        uniquify = True
    )

    # Put extra compiler flags last, in case they're to override earlier flags.
    compile_args.add_all(ctx.attr.copts)
    compile_args.add_all(ctx.fragments.swift.copts())
    compile_args.add_all(ctx.files.srcs)

    compile_inputs = depset(ctx.files.srcs, transitive = swiftmodules + frameworks)

    # Build just the .swiftmodule. This depends on the swiftmodules of its dependencies.
    module_compile_args = ctx.actions.args()
    module_compile_args.add_all(["-emit-module-path", module])
    ctx.actions.run(
        mnemonic = "CompileSwiftModule",
        executable = "xcrun",
        arguments = [compile_args, module_compile_args],
        inputs = compile_inputs,
        outputs = [module],
    )

    object_compile_args = ctx.actions.args()
    object_compile_args.add("-emit-object")

    # To use -num-threads with -whole-module-optimization, an output-file-map is required.
    object_compile_args.add_all(["-num-threads", "8"])
    output_file_map = ctx.actions.declare_file("{}.output-file-map.json".format(module_name))
    object_compile_args.add_all(["-output-file-map", output_file_map])

    object_files = []
    artifacts = {}
    for src in ctx.files.srcs:
        object_file = ctx.actions.declare_file(src.path + ".o")
        object_files.append(object_file)
        artifacts[src.path] = {"object": object_file.path}

    ctx.actions.write(
        output_file_map,
        struct(**artifacts).to_json(),
    )

    # Compile the code. This depends on the .swiftmodule produced above (and its dependencies).
    ctx.actions.run(
        mnemonic = "CompileSwift",
        executable = "xcrun",
        arguments = [compile_args, object_compile_args],
        inputs = depset([module, output_file_map], transitive = [compile_inputs]),
        outputs = object_files,
    )

    libraries = depset(object_files, transitive = [
        dep.transitive_libraries
        for dep in swift_deps
    ])

    return [
        # This ensures the object files are built, since they're not predeclared outputs.
        DefaultInfo(
            files = depset(object_files),
        ),
        SwiftInfo(
            module_name = module_name,
            swift_version = _list_get("-swift-version", ctx.fragments.swift.copts()),
            direct_swiftmodules = [module],
            direct_libraries = object_files,
            transitive_swiftmodules = depset([module], transitive = swiftmodules),
            transitive_libraries = libraries,
            transitive_defines = depset([]),
            transitive_additional_inputs = depset([]),
            transitive_linkopts = depset([]),
        ),
        apple_common.new_objc_provider(
            uses_swift = True,
            library = libraries,
            providers = objc_deps,
        ),
    ]


swift_library = rule(
    implementation = _swift_library_impl,
    fragments = ["apple", "swift"],
    attrs = {
        "module_name": attr.string(),
        "srcs": attr.label_list(allow_files = [".swift"]),
        "deps": attr.label_list(providers = [
            [CcInfo],
            [SwiftClangModuleInfo],
            [SwiftInfo],
            [apple_common.Objc],
        ]),
        "copts": attr.string_list(),
        "alwayslink": attr.bool(default = False),
        "data": attr.label_list(allow_files = True),
        "_xcode_config": attr.label(default = configuration_field(
            fragment = "apple",
            name = "xcode_config_label",
        )),
    },
    outputs = {
        "module": "%{module_name}.swiftmodule",
    }
)

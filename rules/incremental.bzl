load("@build_bazel_rules_swift//swift:swift.bzl", "SwiftInfo", "SwiftClangModuleInfo")

def _drop_ext(path):
    "Return the path with no extension."
    return path[:path.rfind(".")]

def _list_get(key, values):
    "Find the value that follows the key, if any."
    for i in range(len(values)):
        if values[i] == key:
            return values[i + 1]
    return None

def _file_dirname(file):
    return file.dirname

def _string_dirname(path):
    "Return the parent path."
    return path[:path.rfind("/")]

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

def _bazel_sdk(ctx):
    return ctx.fragments.apple.single_arch_platform.name_in_plist.lower()

def _swift_library_impl(ctx):
    module_name = ctx.attr.module_name or ctx.label.name
    module = ctx.actions.declare_file("{}.swiftmodule".format(module_name))
    library = ctx.actions.declare_file("lib{}.a".format(module_name))

    deps = ctx.attr.deps
    swift_deps = [dep[SwiftInfo] for dep in deps if SwiftInfo in dep]
    objc_deps = [dep[apple_common.Objc] for dep in deps if apple_common.Objc in dep]

    swiftmodules = [dep.transitive_swiftmodules for dep in swift_deps]
    frameworks = [dep.static_framework_file for dep in objc_deps]

    # Begin -output-file-map handling code.
    # This is what makes incremental work.

    bindir = ctx.var["BINDIR"]
    incremental_outputs = {}
    for source in ctx.files.srcs:
        # These are incremental artifacts that need to persist between builds, and as
        # such are not declared to Bazel. If they were declared, Bazel would remove them.
        prefix = "{}/Incremental/{}".format(bindir, _drop_ext(source.path))
        incremental_outputs[source.path] = {
            "object": prefix + ".o",
            "swiftmodule": prefix + ".swiftmodule",
            "swift-dependencies": prefix + ".swiftdeps",
        }

    # Empty string key tells swiftc the path to write module incremental state.
    incremental_outputs[""] = {
        "swift-dependencies": "{}/Incremental/{}/{}.swiftdeps".format(bindir, ctx.label.package, module_name),
    }

    output_file_map = ctx.actions.declare_file("{}.output-file-map.json".format(module_name))
    ctx.actions.write(
        output_file_map,
        struct(**incremental_outputs).to_json(),
    )

    # End -output-file-map handling code.

    compile_args = ctx.actions.args()
    compile_args.add_all([
        "-target", _bazel_target(ctx),
        "-module-name", module_name,
        "-incremental", "-driver-show-incremental",
        "-enable-batch-mode",
        "-output-file-map", output_file_map,
        "-emit-module-path", module,
        "-emit-object",
        "-parse-as-library",
    ])

    # TODO: Handle these flags, maybe.
    # -enforce-exclusivity -- match Xcode, but behavior depends on swift-version
    # -enable-testing -- for targets depended on by tests
    # -application-extension -- for targets dependend on by extensions
    # -Xfrontend -serialize-debugging-options -- Xcode adds this

    mode = ctx.var["COMPILATION_MODE"]
    mode_flags = {
        "dbg": ["-Onone", "-g", "-DDEBUG"],
        "fastbuild": ["-Onone", "-gline-tables-only"],
        "opt": ["-O"], # TODO: -g, -wmo
    }
    compile_args.add_all(mode_flags[mode])

    # Set the swiftmodule search paths.
    compile_args.add_all(
        depset(transitive = swiftmodules),
        format_each = "-I%s",
        map_each = _file_dirname,
        uniquify = True,
    )

    # Set the framework search paths.
    compile_args.add_all(
        depset(transitive = [dep.framework_dir for dep in objc_deps]),
        format_each = "-F%s",
        map_each = _string_dirname,
        uniquify = True,
    )

    # Put extra compiler flags last, in case they're to override earlier flags.
    compile_args.add_all(ctx.attr.copts)
    compile_args.add_all(ctx.fragments.swift.copts())

    # Add the source paths.
    compile_args.add_all(ctx.files.srcs)

    ctx.actions.run(
        mnemonic = "CompileSwift",
        executable = ctx.executable._swiftc,
        arguments = [compile_args],
        env = {"xcrun_sdk": _bazel_sdk(ctx)},
        inputs = depset(
            direct = ctx.files.srcs + [output_file_map],
            transitive = swiftmodules + frameworks,
        ),
        outputs = [module, library],
    )

    # Needed by both SwiftInfo and apple_common.Objc.
    libraries = depset([library], transitive = [
        dep.transitive_libraries
        for dep in swift_deps
    ])

    return [
        SwiftInfo(
            module_name = module_name,
            swift_version = _list_get("-swift-version", ctx.fragments.swift.copts()),
            direct_swiftmodules = [module],
            direct_libraries = [library],
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
        "_swiftc": attr.label(
            default = "//tools:swiftc",
            executable = True,
            cfg = "host",
        ),
    },
    # outputs (.swiftmodule and .a) are declared in rule
)

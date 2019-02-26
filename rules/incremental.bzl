load("@build_bazel_rules_swift//swift:swift.bzl", "SwiftInfo")

def _drop_ext(path):
    "Return the path with no extension."
    return path[:path.rfind(".")]

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

def _bazel_sdk(ctx):
    return ctx.fragments.apple.single_arch_platform.name_in_plist.lower()

def _swift_library_impl(ctx):
    module_name = ctx.attr.module_name or ctx.label.name
    module = ctx.actions.declare_file("{}.swiftmodule".format(module_name))
    library = ctx.actions.declare_file("lib{}.a".format(module_name))

    bindir = ctx.var["BINDIR"]

    # Begin -output-file-map handling code.
    # This is what makes incremental work.

    output_file_map = {}
    for source in ctx.files.srcs:
        # These are incremental artifacts that need to persist between builds, and as
        # such are not declared to Bazel. If they were declared, Bazel would remove them.
        prefix = "{}/Incremental/{}".format(bindir, _drop_ext(source.path))
        output_file_map[source.path] = {
            "object": prefix + ".o",
            "swiftmodule": prefix + ".swiftmodule",
            "swift-dependencies": prefix + ".swiftdeps",
        }

    # Empty string key tells swiftc the path to write module incremental state.
    output_file_map[""] = {
        "swift-dependencies": "{}/Incremental/{}/{}.swiftdeps".format(bindir, ctx.label.package, module_name),
    }

    outputs_json = ctx.actions.declare_file("{}.outputs.json".format(module_name))
    ctx.actions.write(
        outputs_json,
        struct(**output_file_map).to_json(),
    )

    # End -output-file-map handling code.

    swiftmodule_inputs = depset(transitive = [
        dep[SwiftInfo].transitive_swiftmodules
        for dep in ctx.attr.deps
    ]).to_list()

    compile_args = [
        "-target", _bazel_target(ctx),
        "-incremental",
        "-driver-show-incremental",
        "-enable-batch-mode",
        "-module-name", module_name,
        "-parse-as-library",
        "-emit-object",
        "-emit-module-path", module.path,
        "-output-file-map", outputs_json.path,
    ]

    # TODO: Handle these flags, maybe.
    # -enforce-exclusivity -- match Xcode, but behavior depends on swift-version
    # -enable-testing -- for targets depended on by tests
    # -application-extension -- for targets dependend on by extensions
    # -Xfrontend -serialize-debugging-options -- Xcode adds this

    mode_flags = {
        "dbg": ["-Onone", "-g", "-DDEBUG"],
        "fastbuild": ["-Onone", "-gline-tables-only"],
        "opt": ["-O"], # TODO: -g, -wmo
    }

    compilation_mode = ctx.var["COMPILATION_MODE"]
    compile_args += mode_flags[compilation_mode]

    # Set the swiftmodule search paths.
    compile_args += ["-I" + f.dirname for f in swiftmodule_inputs]

    # Add the source paths.
    compile_args += [f.path for f in ctx.files.srcs]

    ctx.actions.run(
        mnemonic = "CompileSwift",
        executable = ctx.executable._swiftc,
        arguments = compile_args + ctx.fragments.swift.copts(),
        env = {"xcrun_sdk": _bazel_sdk(ctx)},
        inputs = ctx.files.srcs + swiftmodule_inputs + [outputs_json],
        outputs = [module, library],
    )

    return [SwiftInfo(
        module_name = module_name,
        swift_version = _list_get("-swift-version", ctx.fragments.swift.copts()),
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
    # outputs (.swiftmodule and .a) are declared in rule
)

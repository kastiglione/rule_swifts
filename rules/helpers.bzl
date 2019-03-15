def _list_get(key, values):
    "Find the value that follows the key, if any."
    for i in range(len(values)):
        if values[i] == key:
            return values[i + 1]
    return None

def _dirname(file):
    "Return the parent directory."
    if type(file) == type(""):
        return file[:file.rfind("/")]
    else:
        return file.dirname

def _bazel_target(ctx):
    "Computes the target triple used for compilation."
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
    "Returns the SDK name for the current compilation."
    return ctx.fragments.apple.single_arch_platform.name_in_plist.lower()

helpers = struct(
    list_get = _list_get,
    dirname = _dirname,
    bazel_target = _bazel_target,
    bazel_sdk = _bazel_sdk,
)
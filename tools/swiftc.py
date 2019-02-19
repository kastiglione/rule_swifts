import argparse
import json
import os
import subprocess
import sys

# This wrapper serves two purposes:
#   1. Call libtool to create static libraries
#   2. Ensures output directories exist before use
#   3. Handling of -sdk flag


def _main():
    parser = argparse.ArgumentParser()
    parser.add_argument("-sdk")
    parser.add_argument("-module-name")
    parser.add_argument("-output-file-map")
    parser.add_argument("-emit-module-path")
    args, _ = parser.parse_known_args()

    compile_args = sys.argv[1:]

    # Move `-sdk <appleos>` from swiftc to xcrun.
    xcrun = ["/usr/bin/xcrun"]
    if args.sdk and not os.path.exists(args.sdk):
        xcrun.extend(("-sdk", args.sdk))
        pos = compile_args.index("-sdk")
        del compile_args[pos:pos+2]

    # Determine archive output path.
    module_dir = os.path.dirname(args.emit_module_path)
    archive_name = "lib{}.a".format(args.module_name)
    archive_path = os.path.join(module_dir, archive_name)

    # Collect input object files.
    artifacts = json.load(open(args.output_file_map))
    object_files = [
        mapping["object"]
        for source, mapping in artifacts.items()
        if "object" in mapping
    ]

    # swiftc does not automatically make intermediate directories.
    for path in object_files:
        dir = os.path.dirname(path)
        if not os.path.exists(dir):
            os.makedirs(dir)

    # Pass all args through to swiftc.
    compile = xcrun + ["swiftc"] + compile_args
    subprocess.check_call(compile)

    # Generate the static library.
    archive = xcrun + ["libtool", "-o", archive_path] + object_files
    subprocess.check_call(archive)


if __name__ == "__main__":
    _main()

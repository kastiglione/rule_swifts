### Exploring Swift build strategies.

1. Incremental builds
2. Pipelined (two phase) builds

Pipelined builds run two `swiftc` commands, one that generates a `.swiftmodule`, and one that generates the binaries. Generating a `.swiftmodule` is a subset of compilation, generating just a `.swiftmodule` is faster than full compilation. As an example, module `B` depends on `A`. With pipelined builds, `B` depends on `A.swiftmodule`, not any of `A`'s binaries. By dividing `A`'s compilation into two phases, the first to generate the `A.swiftmodule`, `B` can start compiling sooner, and thus finish sooner.

The strategies live in `rules/`. To try one, edit `Sources/BUILD` and pick the desired Swift build strategy to `load()`.

To build the sample project, run:

```sh
bazel build Sources/C
```

or

```sh
bazel run Sources/runme
```

To visualize the build sequence, build with these extra flags:

```sh
--experimental_generate_json_trace_profile --profile=trace.json
```

Then in Chrome open a tab to `chrome://tracing`, and load or drag in the Bazel generated `.json` event file.

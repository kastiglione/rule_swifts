### Exploring Swift build stragegies.

The strategies live in `rules/`. To try one, edit `Sources/BUILD` and pick the desired Swift build strategy to `load()`.

To build the sample project, run:

```sh
bazel build --spawn_strategy=standalone Sources/C
```

To visualize the build sequence, build with these extra flags:

```sh
--experimental_generate_json_trace_profile --profile=trace.json
```

Then in Chrome open a tab to `chrome://tracing`, and load or drag in the Bazel generated `.json` event file.

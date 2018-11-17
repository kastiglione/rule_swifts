### Exploring Swift build stragegies.

The strategies live in `rules/`. To try one, edit `BUILD` and `load()` the desired strategy.

To build the sample project, run:

```sh
bazel build --spawn_strategy=standalone C
```

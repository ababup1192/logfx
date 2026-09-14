# examples

Code written from the calling side. `make examples` (`ci/example.sh`) builds every one of them
against the `.fpkg` produced from the current source, and runs it.

| | |
|---|---|
| [`quickstart`](quickstart) | The first code block of the README, verbatim. One line out |
| [`server`](server) | Wiring into a server: composing sinks, `LOG_LEVEL`, a span, `Logfx.exception`, a `spawn` per request, and testing the lines with `runWithList` |

Each example has a `verify.sh` that looks at the lines it actually produced.

## Running them

```bash
make examples          # all of them, starting from building the .fpkg
```

To work on one by hand, the version its `flix.toml` names is a released one and resolves on its own:

```bash
cd examples/server
flix run
LOG_LEVEL=debug flix run    # the routing lines appear
flix test
```

## Rules

- **The logfx version in `examples/*/flix.toml` matches the one in the root `flix.toml`.**
  `ci/example.sh` stops when they differ. Raise the version, raise the examples with it
- **A dependency is never written as a path.** Flix dependencies can only be `github:`, and
  escaping to a path would check something other than what a user writes. `ci/example.sh` leaves
  the declaration alone and puts the current `.fpkg` into `lib/` ahead of the resolver
- The way these are written — module names, `\ {IO, Logfx}`, the shape of the tests — follows the
  one project that actually depends on logfx, so that the examples show its house style rather
  than an invented one

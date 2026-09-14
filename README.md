# logfx

Structured logging for [Flix](https://flix.dev). Lines are emitted through a `Logfx` effect;
where they go is a plain value (`Sink`) you compose and swap. Nothing outside the JDK is
required — no Maven dependencies.

```flix
import java.lang.System

let sink = Logfx.Sink.json(_ -> System.currentTimeMillis(), line -> println(line));

Logfx.runWithMin(Logfx.Severity.Info, sink, () -> {
    Logfx.Fields.empty()
        |> Logfx.Fields.str("http.request.method", "GET")
        |> Logfx.Fields.int("http.response.status_code", 200i64)
        |> Logfx.info("request finished")
})
```

```json
{"time":"2026-09-14T07:00:00.000Z","severity":"info","message":"request finished","http.request.method":"GET","http.response.status_code":200}
```

## Install

Add it to `[dependencies]` in your `flix.toml`. There are no Maven dependencies to pull in.

```toml
[dependencies]
"github:ababup1192/logfx" = { version = "0.2.0", security = "unrestricted" }
```

`security = "unrestricted"` is required because `Logfx.exception` calls into
`java.lang.Throwable` (class name, message, cause chain, stack frames). The short form
(`= "0.2.0"`) is rejected by Flix for a package that uses Java interop.

## What you get

| | |
|---|---|
| `Logfx` | The effect. Two operations: `emit` and `enabled` |
| `Logfx.trace` … `Logfx.fatal` | Emit one line. Fields come last, so they pipe |
| `Logfx.traceWith` … `Logfx.fatalWith` | Same, but the fields are built only if the severity is enabled |
| `Logfx.Fields` | Field builder: `str` / `int` (`Int64`) / `float` / `bool` / `strs` / `obj` / `opt` / `value` / `merge` |
| `Logfx.withFields` | A scope (span). Every line emitted inside it carries the fields |
| `Logfx.exception` | `Throwable` → `exception.type` / `.message` / `.cause` / `.stacktrace` |
| `Logfx.Sink` | `Record -> Unit \ IO`. **A value, so callers supply it.** `json` / `silent` / `collect`, composed with `minSeverity` / `enrich` / `tee` / `fallback` |
| `Logfx.runWith`, `Logfx.runWithMin` | The production handler. `runWithMin` drops lines below a severity |
| `Logfx.runWithList` | **The test handler.** Returns the emitted lines as `List[Record]` |
| `Logfx.Value` | What a field holds. Same shape as JSON |

Key names follow the OpenTelemetry semantic conventions (`http.request.method`,
`http.response.status_code`, `exception.type`, …), so Loki and Grafana can count them as they are.

## Filtering, and why there are two ways

```flix
// At the handler: `enabled` answers false, so `infoWith` never builds the map.
Logfx.runWithMin(Logfx.Severity.Warn, sink, () ->
    Logfx.infoWith("expensive", () -> Logfx.Fields.empty() |> Logfx.Fields.str("body", render()))
)

// At the sink: the record is built and then dropped. Use this when one branch of a
// `tee` wants a different threshold than the other.
Logfx.runWith(Logfx.Sink.tee(everything, Logfx.Sink.minSeverity(Logfx.Severity.Error, alerts)), thunk)
```

`Logfx.enabled(severity)` is an operation of the effect, so you can ask it directly before
doing work that only exists for a log line.

## When the sink itself breaks

`runWith` never lets a failing sink escape into your code: at the point the effect operation
runs, the caller's frames are already unwound, so a throw would sail past the caller's `catch`
and skip transaction cleanup. Logging must not take the request down with it.

That silence is a problem of its own, so give the broken case somewhere to go:

```flix
let toStderr = Logfx.Sink.json(clock, line -> System.err.println(line));
let sink = Logfx.Sink.fallback(loki, toStderr);
```

The fallback line reaches `stderr` with `logfx.fallback_reason` added, naming the exception that
killed the primary sink. What the operator needs is the line, not a notification about the line.

## Testing your logs

```flix
let (result, lines) = Logfx.runWithList(() -> handleRequest(req));
```

`runWithList` is pure — no `IO` — and enables every severity, so a test never depends on the
deployment's threshold.

## Design

**The sink is a value.** Writing to a file, shipping to a collector, buffering in a test: all of
that is caller code. This library does not grow output backends. The combinators (`minSeverity`,
`enrich`, `tee`, `fallback`) have the same type, so they just compose.

**`Logfx.Value` is our own.** Borrowing the caller's JSON type inverts the dependency (before this
was extracted, it borrowed a GraphQL `Value`). And the standard `Util.Json.Json` holds every number
as one `BigDecimal`, so `12` comes out as `12.0` — a log backend then types the field as a float.

**Nothing sits at the top level except `Logfx`.** Flix cannot hide modules, so a top-level `Log` or
`Value` would collide with names in the program that depends on it. Everything lives under `Logfx`.

**Broken values stay visibly broken.** `NaN` and `Infinity` become `null` rather than `0`;
`Fields.int` keeps `Int64` rather than clamping to `Int32`. A number that quietly reads
`2147483647` is worse than one that is obviously missing.

## Scope, and what this project will not do

This library was extracted from [flix_graphql_hello](https://github.com/ababup1192/flix_graphql_hello),
a headless CMS written in Flix. It is maintained **only as far as that project needs it**, by one
person, in their spare time.

- **Feature requests are not accepted.** Bug reports and pull requests are welcome.
- **One Flix version is supported** — the one in `flix.toml` (currently 0.75.3). When upstream
  breaks the build, this follows, but no date is promised.
- **Replies can take weeks.** That is the normal case, not a lapse.
- **No output backends are added here** (files, syslog, Loki, OTLP). A `Sink` is a one-line
  function type; write it where you use it.
- **No global/ambient logger, no configuration file, no log rotation.** The handler is the
  configuration.

### When this gets archived

If flix_graphql_hello stops using logfx, this repository is archived and the README says so on the
first line. The last released version keeps working — it is a source package with no Maven
dependencies, pinned to a Flix release. The harm in an unmaintained library is not that it stopped;
it is not knowing whether it stopped. So: that is the condition, written down in advance.

## Versioning

Semantic versioning, with the `0.x` rule spelled out because Flix has no established convention yet:

- **While the version is `0.x`, a minor bump may break you.** Read the release notes before
  moving from `0.1` to `0.2`.
- **Raising the supported Flix version is at least a minor bump**, never a patch.
- Patch releases are fixes that keep the API and the emitted JSON as they were.

The effect `Logfx` is `pub`, so anyone can write their own handler. Adding an operation to it breaks
every hand-written handler, which is why `enabled` landed in 0.2.0 while there were no users at all.

## Development

```bash
make check   # type check
make test    # tests
make consume # build the .fpkg, pull it into a throwaway project, and run it
make pkg     # build the distributable .fpkg
make release # attach .fpkg and flix.toml to a GitHub release
```

The Flix compiler is located by `bin/flix` (pass `FLIX_JAR` to point at a specific jar).

`make consume` is the one that matters before a release: passing your own test suite and being
installable as a package are different things. 0.1.0 type-checked here and could not be compiled by
anyone who did not pass `--Xsubeffecting=lambdas`, because `Sink.silent` returned a pure lambda
where an `IO` one was expected. **logfx requires no experimental compiler flags**; CI runs the same
script on every push, and again against the GitHub release once a tag is pushed.

日本語版は [README.ja.md](README.ja.md)（英語版が正）。

## License

Apache-2.0

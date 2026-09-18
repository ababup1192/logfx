# logfx

*日本語版はこのページの[下半分](#logfx日本語)にあります。英語版が正。*

**Structured logging for [Flix](https://flix.dev).** A line is emitted through a `Logfx` effect;
where it goes is a plain value (`Sink`) you compose and swap. Nothing outside the JDK — no Maven
dependencies, no experimental compiler flags. Built with Flix 0.76.0 from 0.3.3 on (0.3.2 is the last version for 0.75.x).

```flix
import java.lang.System

/// Your code takes the effect, not a logger. Who receives the lines is not decided here.
def handleRequest(method: String, path: String): Int32 \ Logfx =
    Logfx.Fields.empty()
        |> Logfx.Fields.str("http.request.method", method)
        |> Logfx.Fields.str("url.path", path)
        |> Logfx.Fields.int("http.response.status_code", 200i64)
        |> Logfx.info("request finished");
    200

def main(): Unit \ IO =
    let sink = Logfx.Sink.json(_ -> System.currentTimeMillis(), line -> println(line));
    run {
        discard handleRequest("GET", "/posts")
    } with Logfx.runWithMin(Logfx.Severity.Info, sink)
```

```json
{
  "time": "2026-09-14T07:00:00.000Z",
  "severity": "info",
  "message": "request finished",
  "http.request.method": "GET",
  "http.response.status_code": 200,
  "url.path": "/posts"
}
```

That is one line; it is wrapped here so you can read it.

| | |
|---|---|
| Install | `"github:ababup1192/logfx" = { version = "0.3.3", security = "unrestricted" }` under `[dependencies]` |
| API reference | <https://ababup1192.github.io/logfx/Logfx.html> |
| Runnable examples | [`examples/`](examples) — the block above is [`examples/quickstart`](examples/quickstart), and CI compiles it |

`security = "unrestricted"` is required because `Logfx.exception` reads a `java.lang.Throwable`.
The short form (`= "0.3.3"`) is rejected by Flix for a package that uses Java interop.

## What you can do with it

Every JSON block below is one line exactly as it is emitted, wrapped here so you can read it.

**Compose the destination in four lines.** A `Sink` is `Record -> Unit \ IO`, and everything that
wraps one has that same type, so they just nest.

```flix
Logfx.Sink.minSeverity(Logfx.Severity.Info,
    Logfx.Sink.enrich(Logfx.Fields.empty() |> Logfx.Fields.str("service.name", "api"),
        Logfx.Sink.json(clock, line -> println(line))))
```

```json
{
  "time": "2025-09-08T02:53:20.123Z",
  "severity": "info",
  "message": "request finished",
  "service.name": "api",
  "url.path": "/posts"
}
```

`service.name` is on every line without a single call site mentioning it. Writing to a file,
shipping to a collector, buffering in a test — all of that is your code, and it is a `def` you pass
in. This library does not grow output backends.

**Decide the severity from the fields you already collected.** `emit` takes the severity as a
value, and the accessors let a caller read its own attributes back.

```flix
/// A 200 that failed to authenticate is still worth a warning.
def severityOf(path: String, status: Int32, fields: Logfx.Fields): Logfx.Severity =
    if (status >= 500) Logfx.Severity.Error
    else if (status == 401 or status == 403) Logfx.Severity.Warn
    else if (Map.get("auth.result", fields) |> Option.flatMap(Logfx.valueAsStr) == Some("invalid")) Logfx.Severity.Warn
    else if (String.endsWith(suffix = "/health", path)) Logfx.Severity.Debug
    else Logfx.Severity.Info
```

```json
{
  "time": "2025-09-08T02:53:20.123Z",
  "severity": "warn",
  "message": "request",
  "auth.result": "invalid",
  "http.response.status_code": 200,
  "service.name": "api",
  "url.path": "/admin"
}
```

A 200 that is a warning: the status code alone would never have told you. The `/health` line is the
same idea pointed the other way — a health check stops filling the dashboard without leaving the
logs.

**Attach a span once; every line inside carries it.**

```flix
run {
    route(path)                                   // every line in here gets request.id
} with Logfx.withFields(Logfx.Fields.empty() |> Logfx.Fields.str("request.id", "01JC5H"))
```

```json
{"time":"2025-09-08T02:53:20.123Z","severity":"warn","message":"slow query","db.query.duration_ms":812,"request.id":"01JC5H","service.name":"api"}
{"time":"2025-09-08T02:53:20.123Z","severity":"info","message":"request finished","http.response.status_code":200,"request.id":"01JC5H","service.name":"api"}
```

Now `| json | request_id="01JC5H"` pulls back the whole request, including the lines you wrote
three call levels down.

**Turn a caught exception into fields something can count.**

```flix
Logfx.Fields.empty()
    |> Logfx.Fields.int("http.response.status_code", 500i64)
    |> Logfx.exception(error)
    |> Logfx.error("request failed")
```

```json
{
  "time": "2025-09-08T02:53:20.123Z",
  "severity": "error",
  "message": "request failed",
  "exception.message": "connection refused",
  "exception.stacktrace": "Handler.Def$fetchPosts.staticApply(Handler.flix:87) | Handler.Def$listPosts.applyFrame(Handler.flix:59)",
  "exception.type": "java.lang.RuntimeException",
  "http.request.method": "GET",
  "http.response.status_code": 500,
  "request.id": "r2",
  "service.name": "example-server",
  "service.version": "0.0.0",
  "url.path": "/posts"
}
```

`exception.type` is a scalar, so it groups. The stack trace is the Flix frames and nothing else —
see [what logfx trims](#what-logfx-trims-on-the-way-out) for why that matters at 3 a.m.

**Fields are a plain `Map[String, Value]`, so your own merge rule fits.** Two transactions in one
request should add up, not overwrite each other:

```flix
def addCounts(incoming: Logfx.Fields, existing: Logfx.Fields): Logfx.Fields =
    Map.foldLeftWithKey((acc, key, value) -> Map.insert(key, plus(value, Map.get(key, acc)), acc), existing, incoming)

def plus(incoming: Logfx.Value, existing: Option[Logfx.Value]): Logfx.Value = match (existing, incoming) {
    case (Some(Logfx.Value.Int(before)), Logfx.Value.Int(added)) => Logfx.Value.Int(before + added)
    case _                                                      => incoming
}
```

```json
{"time":"2025-09-08T02:53:20.123Z","severity":"info","message":"request finished","db.statements":5,"db.transactions":1,"service.name":"api"}
```

`2 + 3 = 5`, not `3`. A per-request SQL budget is now a number you can alert on.

**Build the expensive fields only if the line is going to exist.** `enabled` is an operation of the
effect, so the answer comes from the handler before anything is built:

```flix
Logfx.debugWith("query plan", () -> Logfx.Fields.empty() |> Logfx.Fields.str("plan", explain(sql)))
```

At a threshold of `Info` this emits nothing **and** `explain(sql)` never runs — 166 ns against the
1,543 ns an emitted line costs. Ask directly with `Logfx.enabled(severity)` when the work is bigger
than one field.

**Keep the request alive when the sink dies.** `runWith` never lets a failing sink escape into your
code: at the point the effect operation runs, the caller's frames are already unwound, so a throw
would sail past the caller's `catch` and skip transaction cleanup. Logging must not take the
request down with it.

Silence is a problem of its own, so name where a broken sink writes instead:

```flix
Logfx.Sink.fallback(toCollector, Logfx.Sink.json(clock, line -> System.err.println(line)))
```

```json
{
  "time": "2025-09-08T02:53:20.123Z",
  "severity": "warn",
  "message": "primary is down",
  "logfx.fallback_reason": "java.lang.RuntimeException: collector unreachable",
  "url.path": "/posts"
}
```

The line itself reaches `stderr`, with the exception that killed the primary added to it. What an
operator needs is the line, not a notification about the line.

**Test what you logged, as values.** `runWithList` is pure — no `IO` — and enables every severity,
so a test never depends on the deployment's threshold.

```flix
let (status, lines) = Logfx.runWithList(() -> handleRequest("r1", "GET", "/nope"));
Assert.assertEq(
    expected = List#{(Logfx.Severity.Warn, "no route")},
    lines |> List.map(record -> (record#severity, record#message)))
```

Assert on the shape of a line, not on its JSON. The key order and the timestamp format are the
library's business; comparing the rendered string makes a test fail on an upgrade that changed
nothing you meant to check.

## The names are the contract

Keys follow the [OpenTelemetry semantic conventions](https://opentelemetry.io/docs/specs/semconv/)
(`http.request.method`, `http.response.status_code`, `exception.type`, …). That is not decoration:
it is what lets a query exist before the incident does.

```logql
{service="api"} | json | request_id="01J..."                                  # one request, every line

sum(rate({service="api"} | json | message="request" | http_response_status_code >= 500 [5m]))
  / sum(rate({service="api"} | json | message="request" [5m])) > 0.01         # 5xx rate over 1%

sum(count_over_time({service="api"} | json | severity="error" [5m])) > 3      # errors are arriving

sum(count_over_time({service="api"} | json | __error__ != "" [5m])) > 0       # lines that are NOT json
```

Two things follow from writing the queries first:

- **One line per request, not three.** The failure belongs in that line's attributes
  (`exception.type`, an error code), because a log backend cannot join two lines.
- **Only `service` is a label.** `request.id`, `url.path` and anything else that varies per request
  goes in the JSON, never in a label — a label per request is an unbounded number of streams.

A key that no query names is a key you are paying to store. That cuts both ways: the field that
tells you *which* thing failed has to be a scalar, or no alert can compare it.

## Wiring it into a server

Everything logfx needs decided lives in one place: your entry point. Your own functions take
`\ Logfx` and nothing more. `IO` shows up only because the work itself does it — or because you
called `Logfx.exception`, which reads a `Throwable`. A function that only logs is `\ Logfx` alone,
and writing `\ Logfx + IO` there is rejected with `Unused effect: 'IO'`.

```flix
def main(): Unit \ IO =
    let sink = Logfx.Sink.enrich(service(), Logfx.Sink.json(_ -> System.currentTimeMillis(), line -> println(line)));
    let min = minSeverity();
    region rc {
        List.forEach(request -> {
            let (requestId, method, path) = request;
            spawn {
                run {
                    Handler.handle(requestId, method, path)
                } with Logfx.runWithMin(min, sink)      // once per thread, at its entry
            } @ rc
        }, incoming())
    }

/// LOG_LEVEL, or Info when it is unset or not a severity.
def minSeverity(): Logfx.Severity \ IO =
    let text: String = System.getenv("LOG_LEVEL");
    if (Object.isNull(text)) Logfx.Severity.Info
    else Logfx.parseSeverity(text) |> Option.getWithDefault(Logfx.Severity.Info)
```

**`runWith` goes inside the `spawn`, not around it.** `Logfx` is an effect, and an effect handler
does not cross a thread — performing `Logfx.info` inside a `spawn` that is merely nested in a
handler fails to compile:

```
Unable to unify the effect formulas: 'Logfx' and '(Chan + IO + NonDet) & e0'.
```

What crosses the thread is the **sink**, because it is a plain value. Build it once at startup and
pass it to every thread. It holds no per-request state, so sharing one is the intended use; what is
per request belongs in a span.

An unknown word in `LOG_LEVEL` is not fatal here on purpose: a server that refuses to start over a
typo in the configuration costs more than logging one severity off.

### Carrying a span onto another thread

A span installed with `withFields` stops at the thread boundary, but the span itself is just a
`Fields` value — and a `Sink` is just a value too. So the way across is to put the span in the sink
before the thread starts:

```flix
let carried = Logfx.Sink.enrich(Logfx.Fields.empty() |> Logfx.Fields.str("request.id", requestId), sink);
spawn {
    run {
        Jobs.perform(kind)                    // takes \ Logfx, knows nothing about any of this
    } with Logfx.runWithMin(min, carried)
} @ rc
```

```json
{"time":"2026-09-14T09:24:25.224Z","severity":"info","message":"job done","job.kind":"webhook","job.outcome":"done","request.id":"r2","service.name":"example-server","service.version":"0.0.0"}
```

Work that no request is waiting for still says which request it came from, and `Jobs.perform` never
learned how. `enrich` is the weakest layer, so a line inside the job can still say something else
under the same key — which is what you want from a default.

The one thing this does not give you is asking, from deep inside a call chain, *what span am I in?*
Nothing reads the accumulated span back out. Build the span where you know it and hand it to the
thread; that is the whole mechanism.

The whole of that, with a span, an exception, a background job on another thread and tests, is
[`examples/server`](examples/server).

## Where a field on a line comes from

Three layers can put a field on the same line. The closer to the line, the stronger:

| | Set by | Strength |
|---|---|---|
| The line | `Logfx.info("m", fields)` | **strongest** — beats both |
| The span | `Logfx.withFields` | beats the sink; an inner span beats an outer one |
| The sink | `Logfx.Sink.enrich` | weakest — a default for every line |

`time`, `severity` and `message` are not fields: `Sink.json` writes them itself and drops any field
by those names, because the same key twice leaves it to whoever reads the JSON to decide which one
survives.

## What logfx trims on the way out

A line is data that leaves the process, so some of it is cut down. All of it is deliberate, and
there is no flag to turn it off:

| | |
|---|---|
| Every string in the fields | Control characters are stripped. JSON escaping would keep a newline from splitting the line, but a terminal escape sequence passes through and can forge one |
| `exception.message` | Cut to 200 characters, and everything from `"Detail:"` onwards is dropped — PostgreSQL puts the offending row (a unique key, an email address) there |
| `exception.cause` | `getCause` is followed 3 links deep. Enough to reach the real reason, and it stops on a cause that cycles |
| `exception.stacktrace` | The Flix frames only (8 at most), written `class.method(file:line)`. A frame with no line number is dropped, and the file is its name, not the absolute path it was compiled from — otherwise the build machine's directory layout is in every error line, which is the line that multiplies on the day the database falls over |
| `NaN`, `Infinity` | Written as `null`. JSON cannot spell them, and `0` would hide that a measurement broke |
| Integers | Kept as `Int64`, so pass an `Int32` through `Int32.toInt64`. A quiet `2147483647` is worse than a number that is obviously missing |

A line with no fields still passes `Logfx.Fields.empty()`; there is no message-only form.

## What a line costs

One line with six fields, rendered as JSON and handed to a sink, is about **1.5 µs** — call it
650,000 lines a second on one core. At one line per request that is 2% of a core at 10,000
requests a second. Measured by `make bench` (Darwin arm64, fastest of seven rounds of 20,000);
`docs/bench/baseline.json` is the recorded result and the thing a change is compared against.

| | |
|---|---:|
| A line, emitted as JSON | 1,543 ns |
| The effect and the handler, with a sink that writes nothing | 604 ns |
| A line the threshold drops | 166 ns |
| `Logfx.exception` on a caught exception | 7,166 ns |

Two of those are worth reading twice. **A dropped line costs a ninth of an emitted one**, which is
why the fields of a `debugWith` go behind a thunk. And **`Logfx.exception` costs more than four
ordinary lines** — walking a stack trace is not cheap, so it belongs on the failure, not on the
request.

This is not the number logfx is best at, and there is nothing here to compare it against: a
measurement of some other library on some other machine is not evidence, so this repository does not
carry one. Most of what is left is building the `Fields` map, and that map is what lets you write
your own merge rule — the cost and the capability are the same decision.

## Design

**The sink is a value.** The combinators (`minSeverity`, `enrich`, `tee`, `fallback`) have the same
type as what they wrap, so they compose without the library knowing any destination. `tee` always
calls both sinks and then rethrows the first exception — the worst day is the one where one sink
breaks and silences the other too.

**`Logfx.Value` is our own.** Borrowing the caller's JSON type inverts the dependency. And the
standard `Util.Json.Json` holds every number as one `BigDecimal`, so `12` comes out as `12.0` and a
log backend types the field as a float.

**Nothing sits at the top level except `Logfx`.** Flix cannot hide modules, so a top-level `Log` or
`Value` would collide with names in the program that depends on it.

## Versioning

Semantic versioning, with the `0.x` rule spelled out because Flix has no established convention yet:

- **While the version is `0.x`, a minor bump may break you.** The
  [release notes](docs/release-notes) say what moved.
- **Raising the supported Flix version is at least a minor bump**, never a patch.
- Patch releases are fixes that keep the API and the emitted JSON as they were.

The effect `Logfx` is `pub`, so anyone can write their own handler. Adding an operation to it breaks
every hand-written handler, which is why `enabled` landed in 0.2.0 while there were no users at all.

## When this gets archived

This library was extracted from a headless CMS written in Flix, developed in a private repository.
If that project stops using logfx, this repository is archived and the README says so on the first
line. The last released version keeps working — it is a source package with no Maven dependencies,
pinned to a Flix release. The harm in an unmaintained library is not that it stopped; it is not
knowing whether it stopped. So: that is the condition, written down in advance.

## Development

```bash
make check        # type check
make check-jargon # watch the Japanese prose for words with an agreed replacement
make test         # tests
make consume      # build the .fpkg, pull it into a throwaway project, and run it
make examples     # build examples/ against the working tree, run its tests and its output
make bench        # measure what one line costs, against docs/bench/baseline.json
make doc          # build the API reference published to GitHub Pages
make pkg          # build the distributable .fpkg
make release      # attach .fpkg and flix.toml to a GitHub release
```

The Flix compiler is located by `bin/flix` (pass `FLIX_JAR` to point at a specific jar).

`make consume` is the one that matters before a release: passing your own test suite and being
installable as a package are different things. 0.1.0 type-checked here and could not be compiled by
anyone who did not pass `--Xsubeffecting=lambdas`, because `Sink.silent` returned a pure lambda
where an `IO` one was expected. CI runs the same script on every push, and again against the GitHub
release once a tag is pushed.

`make examples` compiles `examples/` against the version being developed, so an example that stopped
working is a failed build rather than something a reader discovers. The reference is published by a
tag, never from `main`: a reader must not be looking at an API that no released version has.

## License

Apache-2.0

---

# logfx（日本語）

**Flix の構造化ログ。** `Logfx` effect で 1 行を出し、出力先（Sink）は値として差し替える。
JDK より外の依存は無く、実験フラグも要らない。0.3.3 から Flix 0.76.0 で作っている（0.75.x で使うなら 0.3.2）。

> 上の英語版が正。ずれていたらそちらを見る。

```flix
import java.lang.System

/// 利用側のコードが取るのは effect であって logger ではない。どこへ出るかはここで決めない。
def handleRequest(method: String, path: String): Int32 \ Logfx =
    Logfx.Fields.empty()
        |> Logfx.Fields.str("http.request.method", method)
        |> Logfx.Fields.str("url.path", path)
        |> Logfx.Fields.int("http.response.status_code", 200i64)
        |> Logfx.info("request finished");
    200

def main(): Unit \ IO =
    let sink = Logfx.Sink.json(_ -> System.currentTimeMillis(), line -> println(line));
    run {
        discard handleRequest("GET", "/posts")
    } with Logfx.runWithMin(Logfx.Severity.Info, sink)
```

```json
{
  "time": "2026-09-14T07:00:00.000Z",
  "severity": "info",
  "message": "request finished",
  "http.request.method": "GET",
  "http.response.status_code": 200,
  "url.path": "/posts"
}
```

出るのは 1 行。読めるように折り返してある。

| | |
|---|---|
| 入れる | `flix.toml` の `[dependencies]` に `"github:ababup1192/logfx" = { version = "0.3.3", security = "unrestricted" }` |
| API リファレンス | <https://ababup1192.github.io/logfx/Logfx.html> |
| 動く例 | [`examples/`](examples) — 上の塊がそのまま [`examples/quickstart`](examples/quickstart) で、CI がコンパイルしている |

`security = "unrestricted"` が要るのは、`Logfx.exception` が `java.lang.Throwable` を読むため。
バージョンだけを書く短い形（`= "0.3.2"`）だと Flix が取り込みを断る。

## 何ができるか

下の JSON はどれも実際に出る 1 行で、読めるように折り返してある。

**出力先は 4 行で組める。** `Sink` は `Record -> Unit \ IO` で、それを包む物も全部同じ型なので、
そのまま重なる。

```flix
Logfx.Sink.minSeverity(Logfx.Severity.Info,
    Logfx.Sink.enrich(Logfx.Fields.empty() |> Logfx.Fields.str("service.name", "api"),
        Logfx.Sink.json(clock, line -> println(line))))
```

```json
{
  "time": "2025-09-08T02:53:20.123Z",
  "severity": "info",
  "message": "request finished",
  "service.name": "api",
  "url.path": "/posts"
}
```

`service.name` は全行に付いているが、呼ぶ側のコードはどこにもその名前を書いていない。
ファイルに書く・別の場所へ送る・テストで溜める、はすべて利用側のコードで、渡すのは `def` 1 つ。
ライブラリ側に出力先を増やさない。

**severity は、既に集めた fields から決められる。** `emit` は severity を値で取り、accessor が
自分の属性を読み返せる。

```flix
/// 認証に失敗した 200 は、それでも warn に上げたい。
def severityOf(path: String, status: Int32, fields: Logfx.Fields): Logfx.Severity =
    if (status >= 500) Logfx.Severity.Error
    else if (status == 401 or status == 403) Logfx.Severity.Warn
    else if (Map.get("auth.result", fields) |> Option.flatMap(Logfx.valueAsStr) == Some("invalid")) Logfx.Severity.Warn
    else if (String.endsWith(suffix = "/health", path)) Logfx.Severity.Debug
    else Logfx.Severity.Info
```

```json
{
  "time": "2025-09-08T02:53:20.123Z",
  "severity": "warn",
  "message": "request",
  "auth.result": "invalid",
  "http.response.status_code": 200,
  "service.name": "api",
  "url.path": "/admin"
}
```

200 なのに warn。status code だけを見ていては絶対に出てこない行。`/health` の 1 行は同じ考えを
逆に使った物で、外形監視でダッシュボードを埋めずに、ログには残す。

**span は 1 回付ければ、中の行すべてに付く。**

```flix
run {
    route(path)                                   // ここで出る行には全部 request.id が付く
} with Logfx.withFields(Logfx.Fields.empty() |> Logfx.Fields.str("request.id", "01JC5H"))
```

```json
{"time":"2025-09-08T02:53:20.123Z","severity":"warn","message":"slow query","db.query.duration_ms":812,"request.id":"01JC5H","service.name":"api"}
{"time":"2025-09-08T02:53:20.123Z","severity":"info","message":"request finished","http.response.status_code":200,"request.id":"01JC5H","service.name":"api"}
```

これで `| json | request_id="01JC5H"` が 1 リクエスト分を全部引く。3 段下で書いた行も一緒に来る。

**捕まえた例外は、集計できるフィールドになる。**

```flix
Logfx.Fields.empty()
    |> Logfx.Fields.int("http.response.status_code", 500i64)
    |> Logfx.exception(error)
    |> Logfx.error("request failed")
```

```json
{
  "time": "2025-09-08T02:53:20.123Z",
  "severity": "error",
  "message": "request failed",
  "exception.message": "connection refused",
  "exception.stacktrace": "Handler.Def$fetchPosts.staticApply(Handler.flix:87) | Handler.Def$listPosts.applyFrame(Handler.flix:59)",
  "exception.type": "java.lang.RuntimeException",
  "http.request.method": "GET",
  "http.response.status_code": 500,
  "request.id": "r2",
  "service.name": "example-server",
  "service.version": "0.0.0",
  "url.path": "/posts"
}
```

`exception.type` はスカラーなので、そのまま group by できる。stacktrace は Flix の frame だけで、
その理由は[出る途中で削る物](#logfx-が出る途中で削る物)にある。深夜 3 時に効いてくる。

**Fields はただの `Map[String, Value]` なので、独自のマージ規則が書ける。** 1 リクエストで
Tx を 2 回張ったら、上書きではなく足したい:

```flix
def addCounts(incoming: Logfx.Fields, existing: Logfx.Fields): Logfx.Fields =
    Map.foldLeftWithKey((acc, key, value) -> Map.insert(key, plus(value, Map.get(key, acc)), acc), existing, incoming)

def plus(incoming: Logfx.Value, existing: Option[Logfx.Value]): Logfx.Value = match (existing, incoming) {
    case (Some(Logfx.Value.Int(before)), Logfx.Value.Int(added)) => Logfx.Value.Int(before + added)
    case _                                                      => incoming
}
```

```json
{"time":"2025-09-08T02:53:20.123Z","severity":"info","message":"request finished","db.statements":5,"db.transactions":1,"service.name":"api"}
```

`3` ではなく `2 + 3 = 5`。1 リクエストあたりの SQL の上限が、アラートを書ける数字になる。

**重い fields は、行が本当に出る時だけ組み立てる。** `enabled` は effect の op なので、
組み立てる前に handler が答える:

```flix
Logfx.debugWith("query plan", () -> Logfx.Fields.empty() |> Logfx.Fields.str("plan", explain(sql)))
```

段が `Info` なら行が出ないだけでなく、`explain(sql)` も走らない。166 ns で、出す行の 1,543 ns に対して
9 分の 1。フィールド 1 つより大きい仕事なら `Logfx.enabled(severity)` で直接訊く。

**Sink が壊れてもリクエストは死なない。** `runWith` は sink の例外を呼ぶ側に漏らさない。
effect の op が走る時点で呼ぶ側の frame は巻き戻っていて、投げても呼ぶ側の `catch` を素通りし、
Tx の後始末が飛ぶため。ログの失敗で業務を落とさない。

黙って消えるのも困るので、壊れた時の行き先を書く:

```flix
Logfx.Sink.fallback(toCollector, Logfx.Sink.json(clock, line -> System.err.println(line)))
```

```json
{
  "time": "2025-09-08T02:53:20.123Z",
  "severity": "warn",
  "message": "primary is down",
  "logfx.fallback_reason": "java.lang.RuntimeException: collector unreachable",
  "url.path": "/posts"
}
```

行そのものが stderr に出る。primary を殺した例外が付いた形で。運用者が要るのは通知ではなく、
消えたはずの行そのもの。

**出したログは値としてテストできる。** `runWithList` は純粋（`IO` が付かない）で全段を有効に
するので、本番の段の設定にテストが引きずられない。

```flix
let (status, lines) = Logfx.runWithList(() -> handleRequest("r1", "GET", "/nope"));
Assert.assertEq(
    expected = List#{(Logfx.Severity.Warn, "no route")},
    lines |> List.map(record -> (record#severity, record#message)))
```

比べるのは行の形であって、JSON の文字列ではない。キーの順と時刻の形はライブラリ側の仕事なので、
文字列で比べると、意味の変わっていないバージョン上げでテストが落ちる。

## キーの名前が契約

キーは [OpenTelemetry の意味づけ規約](https://opentelemetry.io/docs/specs/semconv/)に合わせてある
（`http.request.method`、`http.response.status_code`、`exception.type` …）。これは飾りではなく、
障害が起きる前にクエリを書いておけるかどうかの話。

```logql
{service="api"} | json | request_id="01J..."                                  # 1 リクエストの行を全部

sum(rate({service="api"} | json | message="request" | http_response_status_code >= 500 [5m]))
  / sum(rate({service="api"} | json | message="request" [5m])) > 0.01         # 5xx の率が 1% を超えた

sum(count_over_time({service="api"} | json | severity="error" [5m])) > 3      # error が届き始めた

sum(count_over_time({service="api"} | json | __error__ != "" [5m])) > 0       # JSON でない行
```

クエリを先に書くと、2 つの決めが自然に出てくる:

- **1 リクエスト 1 行。** 失敗の中身（`exception.type`、エラーコード）はその行の属性にする。
  ログ基盤は 2 つの行を join できない。
- **ラベルは `service` だけ。** `request.id` や `url.path` のようにリクエストごとに変わる物は
  JSON に入れ、ラベルにしない。リクエストごとのラベルはストリームを無限に増やす。

どのクエリも名前を呼ばないキーは、置いておくだけで金を払っているキー。逆も言えて、
「何が失敗したか」を伝えるフィールドはスカラーでないと、アラートが比較できない。

## サーバに組み込む

logfx について決める事は全部 1 か所（入口）に集まる。利用側の関数に付く効果は `\ Logfx` だけ。
`IO` が増えるのは、仕事の方が触るか、`Throwable` を読む `Logfx.exception` を呼んだ時。ログしか
しない関数は `\ Logfx` のみで、`\ Logfx + IO` と書くと `Unused effect: 'IO'` で断られる。

```flix
def main(): Unit \ IO =
    let sink = Logfx.Sink.enrich(service(), Logfx.Sink.json(_ -> System.currentTimeMillis(), line -> println(line)));
    let min = minSeverity();
    region rc {
        List.forEach(request -> {
            let (requestId, method, path) = request;
            spawn {
                run {
                    Handler.handle(requestId, method, path)
                } with Logfx.runWithMin(min, sink)      // スレッド 1 本につき 1 回、その入口で
            } @ rc
        }, incoming())
    }

/// LOG_LEVEL から。無い時と知らない語は Info。
def minSeverity(): Logfx.Severity \ IO =
    let text: String = System.getenv("LOG_LEVEL");
    if (Object.isNull(text)) Logfx.Severity.Info
    else Logfx.parseSeverity(text) |> Option.getWithDefault(Logfx.Severity.Info)
```

**`runWith` は `spawn` の内側に置く。外側ではない。** `Logfx` は effect で、effect の handler は
スレッドを越えない。handler の中に置いただけの `spawn` の中で `Logfx.info` を呼ぶとコンパイルが
落ちる:

```
Unable to unify the effect formulas: 'Logfx' and '(Chan + IO + NonDet) & e0'.
```

スレッドを越えるのは **Sink** の方。値なので、起動時に 1 本組んで全スレッドに渡す。リクエスト
ごとの状態を持たないので共有するのが本来の使い方で、リクエストごとの物は span に置く。

`LOG_LEVEL` の知らない語でわざと落とさないのは、設定の綴り違いでサーバが起動しない方が、
1 段ずれてログが出る事より高く付くため。

### span を別のスレッドへ運ぶ

`withFields` で張った span はスレッドの境目で止まる。ただし span そのものは `Fields` という値で、
`Sink` もまた値。だから渡り方は、**スレッドが始まる前に span を Sink に入れておく**事:

```flix
let carried = Logfx.Sink.enrich(Logfx.Fields.empty() |> Logfx.Fields.str("request.id", requestId), sink);
spawn {
    run {
        Jobs.perform(kind)                    // \ Logfx を取るだけ。この事情を何も知らない
    } with Logfx.runWithMin(min, carried)
} @ rc
```

```json
{"time":"2026-09-14T09:24:25.224Z","severity":"info","message":"job done","job.kind":"webhook","job.outcome":"done","request.id":"r2","service.name":"example-server","service.version":"0.0.0"}
```

誰も待っていない仕事の行にも、どのリクエストから来たかが付く。`Jobs.perform` はその方法を
一度も知らない。`enrich` は一番弱い層なので、job の中の行が同じキーで別の事を言う余地も残る。
既定値に求めるのはその性質。

これで足りないのは 1 つだけ。呼び出しの奥から「**今の span は何か**」を訊く事はできない。
溜まった span を読み返す口が無いため。span は分かっている所で組んでスレッドに渡す——仕組みはそれだけ。

span・exception・別スレッドの job・テストまで入った全体が [`examples/server`](examples/server)。

## 同じ行のフィールドは 3 か所から来る

行に近い方が強い。

| | 付ける所 | 強さ |
|---|---|---|
| 行 | `Logfx.info("m", fields)` | **一番強い**（span も sink も上書きする） |
| span | `Logfx.withFields` | sink より強い。span の入れ子は内側が勝つ |
| sink | `Logfx.Sink.enrich` | 一番弱い。全行の既定値 |

`time` / `severity` / `message` はフィールドではない。`Sink.json` が自分で書き、その名前の
フィールドは捨てる。同じキーが 2 度出ると、どちらが残るかが JSON を読む側任せになるため。

## logfx が出る途中で削る物

行はプロセスの外に出るデータなので、出る途中で削る物がある。全部わざとで、外す設定は無い。

| | |
|---|---|
| fields の全文字列 | 制御文字を落とす。JSON の escape でも改行で行は割れないが、端末のエスケープシーケンスは通り、偽の行を作れる |
| `exception.message` | 200 字で切り、`"Detail:"` 以降を落とす。PostgreSQL がそこに行の値（一意キー・メールアドレス）を入れるため |
| `exception.cause` | `getCause` を 3 段まで。本当の理由に届く深さで、循環した cause でも止まる |
| `exception.stacktrace` | Flix の frame だけ 8 つ。形は `クラス.メソッド(ファイル名:行)`。行番号の無い frame は捨てる。ファイルは名前だけで、コンパイル時の絶対パスは出さない（ビルドマシンのディレクトリ構成が全エラー行に入る。DB が落ちた日に一番増えるのがその行） |
| `NaN` / 無限大 | `null` で出す。JSON に書き方が無く、`0` にすると計測が壊れた事が消える |
| 整数 | `Int64` のまま。`Int32` は `Int32.toInt64` で渡す。静かに読める `2147483647` の方が、明らかに欠けている数より悪い |

fields の無い行も `Logfx.Fields.empty()` を渡す。message だけの形は無い。

## 1 行の値段

フィールド 6 つの行を JSON にして sink に渡すまでが **約 1.5 µs**。1 コアで毎秒 65 万行、
1 リクエスト 1 行なら毎秒 1 万リクエストで CPU の 2%。`make bench` で測った値（Darwin arm64、
20,000 回 × 7 ラウンドの最速）で、記録は `docs/bench/baseline.json` にあり、変更はそこと比べる。

| | |
|---|---:|
| 1 行を JSON で出し切るまで | 1,543 ns |
| effect と handler だけ（何も書かない sink） | 604 ns |
| 段で落ちる行 | 166 ns |
| 捕まえた例外に `Logfx.exception` | 7,166 ns |

このうち 2 つは読み返す価値がある。**落とす行は出す行の 9 分の 1** で、これが `debugWith` の
fields を thunk の後ろに置く理由。そして **`Logfx.exception` は普通の行 4 本分より高い**。
stack trace を辿るのは安くないので、失敗の行に付ける物であって、リクエストの行に付ける物ではない。

ここは logfx が一番得意な所ではない。そして比べる相手は置かない。別のライブラリを別の機械で
測った数字は根拠にならないので、このリポジトリは持たない。残っているコストの大半は `Fields` の
`Map` を組む所で、その `Map` は独自のマージ規則を書ける理由でもある。**値段と自由は同じ判断の裏表。**

## 設計

**Sink は値。** 重ねる物（`minSeverity` / `enrich` / `tee` / `fallback`）は包む相手と同じ型なので、
ライブラリが出力先を 1 つも知らないまま繋がる。`tee` は必ず両方に渡してから最初の例外を投げ直す。
片方が壊れた日にもう片方まで黙るのが一番困るため。

**`Logfx.Value` を自前で持つ。** 利用側の JSON の型を借りると依存の向きが逆になる。もう 1 つは、
標準の `Util.Json.Json` は数を `BigDecimal` 1 つで持つので、`12` が `12.0` として出て、ログ基盤が
小数の型で取ってしまう。

**トップレベルに一般名を置かない。** Flix はモジュールを隠せないので、`Log` や `Value` を
トップレベルに置くと利用側と衝突する。

## バージョンの付け方

semver。Flix にはまだ慣行が無いので `0.x` の規則を明文化する:

- **`0.x` の間は minor で壊す事がある。** 何が動いたかは
  [release note](docs/release-notes) に書く。
- **対応する Flix のバージョンを上げる時は必ず minor 以上。** patch にはしない。
- patch は API と出る JSON を変えない修正だけ。

`Logfx` は `pub` な effect なので、handler は誰でも書ける。op を足すと自前の handler を書いた
利用者が全員壊れる。だから `enabled` は、利用者が 0 人の 0.2.0 で入れた。

## アーカイブする条件

これは非公開のリポジトリで作っている Flix 製のヘッドレス CMS から切り出した物。そのプロジェクトが
logfx を使わなくなったら、このリポジトリはアーカイブして README の 1 行目にそう書く。その時点の
バージョンはそのまま動く（Maven 依存の無いソースのパッケージで、Flix の release に固定されている）。
放置されたライブラリの害は「止まっていること」より「止まっているか分からないこと」なので、
条件を先に書いておく。

## 開発

```bash
make check        # 型検査
make check-jargon # 日本語に、言い換え先のある語が残っていないか
make test         # テスト
make consume      # .fpkg を作り、捨てプロジェクトから取り込んで動かす
make examples     # examples/ を今のソースに対してビルドし、テストと出力を確かめる
make bench        # 1 行のコストを測り、docs/bench/baseline.json と比べる
make doc          # GitHub Pages に出す API リファレンス
make pkg          # 配布用の .fpkg
make release      # GitHub の release に .fpkg と flix.toml を付ける
```

Flix コンパイラは `bin/flix` が解決する（`FLIX_JAR` を渡せばそれを使う）。

release の前に効くのは `make consume`。自分のテストに通る事と、パッケージとして取り込める事は
別物で、0.1.0 は手元では緑のまま、`--Xsubeffecting=lambdas` を付けない人にはコンパイルできなかった
（`Sink.silent` が純粋なラムダを `IO` の所に返していた）。CI は push ごとに同じ script を回し、
tag を打った後は GitHub の release からも取り込んで確かめる。

`make examples` は `examples/` を開発中のバージョンに対してコンパイルする。動かなくなった例が
「読んだ人が気づく物」ではなく「ビルドの失敗」になる。リファレンスは tag からだけ公開する。
どの release にも無い API を読んでいる、という状態を読む側から見分けられないため。

## ライセンス

Apache-2.0

# logfx

*日本語版はこのページの[下半分](#logfx日本語)にあります。英語版が正。*

Structured logging for [Flix](https://flix.dev). Lines are emitted through a `Logfx` effect;
where they go is a plain value (`Sink`) you compose and swap. Nothing outside the JDK is
required — no Maven dependencies.

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
{"time":"2026-09-14T07:00:00.000Z","severity":"info","message":"request finished","http.request.method":"GET","http.response.status_code":200,"url.path":"/posts"}
```

That whole block is [`examples/quickstart`](examples/quickstart), compiled by `make examples` —
it is the source, and this README is the copy. A fuller one, with a span, an exception, a `spawn`
per request and tests, is [`examples/server`](examples/server).

## Install

Add it to `[dependencies]` in your `flix.toml`. There are no Maven dependencies to pull in.

```toml
[dependencies]
"github:ababup1192/logfx" = { version = "0.2.1", security = "unrestricted" }
```

It is built with **Flix 0.75.3** and needs no experimental compiler flags.

`security = "unrestricted"` is required because `Logfx.exception` calls into
`java.lang.Throwable` (class name, message, cause chain, stack frames). The short form
(`= "0.2.1"`) is rejected by Flix for a package that uses Java interop.

## What you get

The generated API reference is at **<https://ababup1192.github.io/logfx/Logfx.html>**.
The table below is the map; the reference is the territory.


| | |
|---|---|
| `Logfx` | The effect. Two operations: `emit` and `enabled` |
| `Logfx.trace` … `Logfx.fatal` | Emit one line. Fields come last, so they pipe |
| `Logfx.traceWith` … `Logfx.fatalWith` | Same, but the fields are built only if the severity is enabled |
| `Logfx.Fields` | Field builder: `str` / `int` / `float` / `bool` / `strs` / `obj` / `opt` / `value` / `merge`. `int` takes an `Int64`, so pass an `Int32` through `Int32.toInt64` |
| `Logfx.withFields` | A scope (span). Every line emitted inside it carries the fields |
| `Logfx.exception` | `Throwable` → `exception.type` / `.message` / `.cause` / `.stacktrace` |
| `Logfx.Sink` | `Record -> Unit \ IO`. **A value, so callers supply it.** `json` / `silent` / `collect`, composed with `minSeverity` / `enrich` / `tee` / `fallback` |
| `Logfx.runWith`, `Logfx.runWithMin` | The production handler. `runWithMin` drops lines below a severity |
| `Logfx.runWithList` | **The test handler.** Returns the emitted lines as `List[Record]` |
| `Logfx.Value` | What a field holds. Same shape as JSON, with accessors `valueAsStr` … `valueIsNull` for writing a sink |
| `Logfx.parseSeverity` | `"warn"` → `Severity.Warn`, for reading a `LOG_LEVEL` out of the environment |
| `Logfx.toJsonLine` | The line renderer, if you want the JSON without `Sink.json` |

Key names follow the OpenTelemetry semantic conventions (`http.request.method`,
`http.response.status_code`, `exception.type`, …), so Loki and Grafana can count them as they are.

## Wiring it into a server

Everything logfx needs decided lives in one place: your entry point. Your own code takes the
`Logfx` effect and nothing else.

```flix
def main(): Unit \ IO =
    let sink = Logfx.Sink.enrich(service(), Logfx.Sink.json(_ -> System.currentTimeMillis(), line -> println(line)));
    let min = minSeverity();
    region rc {
        List.forEach(request -> {
            let (requestId, method, path) = request;
            spawn {
                run {
                    Example.Handler.handle(requestId, method, path)
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

**`runWith` goes inside the `spawn`, not around it.** `Logfx` is an effect, and an effect
handler does not cross a thread — performing `Logfx.info` inside a `spawn` that is merely
nested in a handler fails to compile:

```
Unable to unify the effect formulas: 'Logfx' and '(Chan + IO + NonDet) & e0'.
```

What crosses the thread is the **sink**, because it is a plain value. Build it once at startup
and pass it to every thread.

A `Sink` holds no per-request state, so sharing one is the intended use. Anything per request
belongs in a span instead:

```flix
run {
    route(path)
} with Logfx.withFields(Logfx.Fields.empty() |> Logfx.Fields.str("request.id", requestId))
```

## Where a field on a line comes from

Three layers can put a field on the same line. The closer to the line, the stronger:

| | Set by | Strength |
|---|---|---|
| The line | `Logfx.info("m", fields)` | **strongest** — beats both |
| The span | `Logfx.withFields` | beats the sink; an inner span beats an outer one |
| The sink | `Logfx.Sink.enrich` | weakest — a default for every line |

`time`, `severity` and `message` are not fields: `Sink.json` writes them itself and drops any
field by those names, because the same key twice leaves it to whoever reads the JSON to decide
which one survives.

## Filtering, and why there are two ways

```flix
// At the handler: `enabled` answers false, so `infoWith` never builds the map.
run {
    Logfx.infoWith("expensive", () -> Logfx.Fields.empty() |> Logfx.Fields.str("body", render()))
} with Logfx.runWithMin(Logfx.Severity.Warn, sink)

// At the sink: the record is built and then dropped. Use this when one branch of a
// `tee` wants a different threshold than the other.
run {
    thunk()
} with Logfx.runWith(Logfx.Sink.tee(everything, Logfx.Sink.minSeverity(Logfx.Severity.Error, alerts)))
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

`tee` always calls both sinks, then rethrows the first exception. The worst day is the one where
one sink breaks and silences the other too — so `fallback(tee(a, b), stderr)` sends the line to
`stderr` when *either* `a` or `b` throws, after both have had it.

## What logfx changes about your values

A line is data that leaves the process, so some of it is trimmed on the way out. Everything here
is deliberate, and there is no flag to turn it off:

| | |
|---|---|
| Every string in the fields | Control characters are stripped. JSON escaping would keep a newline from splitting the line, but a terminal escape sequence passes through and can forge one |
| `exception.message` | Cut to 200 characters, and everything from `"Detail:"` onwards is dropped — PostgreSQL puts the offending row (a key, an email address) there |
| `exception.cause` | `getCause` is followed 3 links deep. Enough to reach the real reason, and it stops on a cause that cycles |
| `exception.stacktrace` | The Flix frames only (8 at most). `dev.flix.runtime` and JDK frames do not say where you are, and on the day the database falls over they pile up 3 KB per line |
| `NaN`, `Infinity` | Written as `null`. JSON cannot spell them, and `0` would hide that a measurement broke |
| Integers | Kept as `Int64`. A quiet `2147483647` is worse than a number that is obviously missing |

## Testing your logs

```flix
let (status, lines) = Logfx.runWithList(() -> handleRequest("r1", "GET", "/nope"));
```

`runWithList` is pure — no `IO` — and enables every severity, so a test never depends on the
deployment's threshold.

Assert on the shape of a line, not on its JSON. The key order and the timestamp format are the
library's business; comparing the rendered string makes a test fail on a logfx upgrade that
changed nothing you meant to check.

```flix
Assert.assertEq(
    expected = List#{(Logfx.Severity.Warn, "no route", List#{"request.id", "url.path"})},
    List.map(record -> (record#severity, record#message, Map.keysOf(record#fields) |> Set.toList), lines))
```

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

## When this gets archived

This library was extracted from a headless CMS written in Flix, developed in a private
repository. If that project stops using logfx, this repository is archived and
the README says so on the first line. The last released version keeps working — it is a source
package with no Maven dependencies, pinned to a Flix release. The harm in an unmaintained library is not that it stopped;
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
make check    # type check
make test     # tests
make consume  # build the .fpkg, pull it into a throwaway project, and run it
make examples # build examples/ against the working tree, run its tests and its output
make doc      # build the API reference published to GitHub Pages
make pkg      # build the distributable .fpkg
make release  # attach .fpkg and flix.toml to a GitHub release
```

The Flix compiler is located by `bin/flix` (pass `FLIX_JAR` to point at a specific jar).

`make consume` is the one that matters before a release: passing your own test suite and being
installable as a package are different things. 0.1.0 type-checked here and could not be compiled by
anyone who did not pass `--Xsubeffecting=lambdas`, because `Sink.silent` returned a pure lambda
where an `IO` one was expected. **logfx requires no experimental compiler flags**; CI runs the same
script on every push, and again against the GitHub release once a tag is pushed.

`make examples` compiles `examples/` against the version being developed, so an example that
stopped working is a failed build rather than something a reader discovers. The reference is
published by a tag, never from `main`: a reader must not be looking at an API that no released
version has.

## License

Apache-2.0

---

# logfx（日本語）

Flix の構造化ログ。`Logfx` effect で 1 行を出し、出力先（Sink）は値として差し替える。
JDK より外の依存は無い。

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
{"time":"2026-09-14T07:00:00.000Z","severity":"info","message":"request finished","http.request.method":"GET","http.response.status_code":200,"url.path":"/posts"}
```

この塊がそのまま [`examples/quickstart`](examples/quickstart) で、`make examples` がビルドする。
あちらが本体で、この README が写し。span・exception・リクエストごとの `spawn`・テストまで入った
版は [`examples/server`](examples/server)。

## 入れる

`flix.toml` の `[dependencies]` に書く。Maven の依存は無いので、利用側で足す物は無い。

```toml
[dependencies]
"github:ababup1192/logfx" = { version = "0.2.1", security = "unrestricted" }
```

**Flix 0.75.3** で作っていて、実験フラグは要らない。

`security = "unrestricted"` が要るのは、`Logfx.exception` が `java.lang.Throwable`
（クラス名・message・cause の連鎖・stack frame）を触るため。版だけを書く短い形
（`= "0.2.1"`）だと Flix が取り込みを断る。

## 持っている物

生成した API リファレンスは **<https://ababup1192.github.io/logfx/Logfx.html>**。
下の表は地図で、リファレンスが現地。

| | |
|---|---|
| `Logfx` | effect。op は `emit` と `enabled` の 2 つ |
| `Logfx.trace` … `Logfx.fatal` | 1 行出す。fields は最後（パイプで受ける） |
| `Logfx.traceWith` … `Logfx.fatalWith` | 同じだが、その段が有効な時だけ fields を組み立てる |
| `Logfx.Fields` | フィールドのビルダー。`str` / `int` / `float` / `bool` / `strs` / `obj` / `opt` / `value` / `merge`。`int` は `Int64` なので、`Int32` は `Int32.toInt64` で渡す |
| `Logfx.withFields` | 入れ子の文脈（span）。中で出る行すべてにフィールドが付く |
| `Logfx.exception` | `Throwable` から `exception.type` / `.message` / `.cause` / `.stacktrace` |
| `Logfx.Sink` | `Record -> Unit \ IO`。**値なので利用側が差せる**。`json` / `silent` / `collect` と、重ねる `minSeverity` / `enrich` / `tee` / `fallback` |
| `Logfx.runWith`, `Logfx.runWithMin` | 本番の handler。`runWithMin` は段より軽い行を落とす |
| `Logfx.runWithList` | **テスト用の handler。** 出た行を `List[Record]` で受け取る |
| `Logfx.Value` | フィールドに入る値。JSON と同じ形。Sink を書く時の `valueAsStr` … `valueIsNull` も付いている |
| `Logfx.parseSeverity` | `"warn"` → `Severity.Warn`。環境変数の `LOG_LEVEL` を読む用 |
| `Logfx.toJsonLine` | 行を JSON にする所。`Sink.json` を通さずに文字列だけ欲しい時に |

キーの名前は OpenTelemetry の意味づけ規約（`http.request.method`、
`http.response.status_code`、`exception.type` …）に合わせてある。Loki や Grafana で
そのまま数えられる。

## サーバに組み込む

logfx について決める事は全部 1 か所（入口）に集まる。利用側のコードが取るのは `Logfx` effect だけ。

```flix
def main(): Unit \ IO =
    let sink = Logfx.Sink.enrich(service(), Logfx.Sink.json(_ -> System.currentTimeMillis(), line -> println(line)));
    let min = minSeverity();
    region rc {
        List.forEach(request -> {
            let (requestId, method, path) = request;
            spawn {
                run {
                    Example.Handler.handle(requestId, method, path)
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
スレッドを越えない。handler の中に置いただけの `spawn` の中で `Logfx.info` を呼ぶとコンパイルが落ちる:

```
Unable to unify the effect formulas: 'Logfx' and '(Chan + IO + NonDet) & e0'.
```

スレッドを越えるのは **Sink** の方。値なので、起動時に 1 本組んで全スレッドに渡す。

`Sink` はリクエストごとの状態を持たないので、共有するのが本来の使い方。リクエストごとの物は span に置く:

```flix
run {
    route(path)
} with Logfx.withFields(Logfx.Fields.empty() |> Logfx.Fields.str("request.id", requestId))
```

## 同じ行のフィールドは 3 か所から来る

行に近い方が強い。

| | 付ける所 | 強さ |
|---|---|---|
| 行 | `Logfx.info("m", fields)` | **一番強い**（span も sink も上書きする） |
| span | `Logfx.withFields` | sink より強い。span の入れ子は内側が勝つ |
| sink | `Logfx.Sink.enrich` | 一番弱い。全行の既定値 |

`time` / `severity` / `message` はフィールドではない。`Sink.json` が自分で書き、その名前の
フィールドは捨てる。同じキーが 2 度出ると、どちらが残るかが JSON を読む側任せになるため。

## 段の絞り方が 2 つある理由

```flix
// handler で絞る。enabled が false を返すので、infoWith は Map を組み立てない。
run {
    Logfx.infoWith("expensive", () -> Logfx.Fields.empty() |> Logfx.Fields.str("body", render()))
} with Logfx.runWithMin(Logfx.Severity.Warn, sink)

// Sink で絞る。Record は組み上がってから捨てられる。tee の片側だけ段を変えたい時に使う。
run {
    thunk()
} with Logfx.runWith(Logfx.Sink.tee(everything, Logfx.Sink.minSeverity(Logfx.Severity.Error, alerts)))
```

`Logfx.enabled(severity)` は effect の op なので、ログのためだけの計算をする前に直接訊ける。

## sink 自身が壊れた時

`runWith` は sink の例外を呼ぶ側に漏らさない。effect の op が走る時点で呼ぶ側の frame は
巻き戻っていて、投げても呼ぶ側の `catch` を素通りし、Tx の後始末が飛ぶため。ログの失敗で
業務を落とさない。

ただし黙って消えるのも困るので、壊れた時の行き先を書く:

```flix
let toStderr = Logfx.Sink.json(clock, line -> System.err.println(line));
let sink = Logfx.Sink.fallback(loki, toStderr);
```

行は `logfx.fallback_reason`（primary を殺した例外）付きで stderr に出る。運用者が要るのは
通知ではなく、消えたはずの行そのもの。

`tee` は必ず両方に渡してから、最初の例外を投げ直す。片方が壊れた日にもう片方まで黙るのが
一番困るため。なので `fallback(tee(a, b), stderr)` は、`a` と `b` の**どちらか**が投げた時に、
両方に渡し終えてから行を stderr に出す。

## logfx が値に手を入れる所

行はプロセスの外に出るデータなので、出る途中で削る物がある。全部わざとで、外す設定は無い。

| | |
|---|---|
| fields の全文字列 | 制御文字を落とす。JSON の escape でも改行で行は割れないが、端末のエスケープシーケンスは通り、偽の行を作れる |
| `exception.message` | 200 字で切り、`"Detail:"` 以降を落とす。PostgreSQL がそこに行の値（鍵・メールアドレス）を入れるため |
| `exception.cause` | `getCause` を 3 段まで。本当の理由に届く深さで、循環した cause でも止まる |
| `exception.stacktrace` | Flix の frame だけ 8 つ。`dev.flix.runtime` や JDK の frame は場所を教えず、DB が落ちた日に 1 行 3 KB 積もる |
| `NaN` / 無限大 | `null` で出す。JSON に書き方が無く、`0` にすると計測が壊れた事が消える |
| 整数 | `Int64` のまま。静かに読める `2147483647` の方が、明らかに欠けている数より悪い |

## ログをテストする

```flix
let (status, lines) = Logfx.runWithList(() -> handleRequest("r1", "GET", "/nope"));
```

`runWithList` は純粋（`IO` が付かない）で、全段を有効にする。本番の段の設定にテストが
引きずられない。

比べるのは行の形であって、JSON の文字列ではない。キーの順と時刻の形はライブラリ側の仕事なので、
文字列で比べると、意味の変わっていない版上げでテストが落ちる。

```flix
Assert.assertEq(
    expected = List#{(Logfx.Severity.Warn, "no route", List#{"request.id", "url.path"})},
    List.map(record -> (record#severity, record#message, Map.keysOf(record#fields) |> Set.toList), lines))
```

## 設計

**Sink は値。** ファイルに書く・別の場所へ送る・テストで溜める、はすべて利用側で書ける。
ライブラリ側に出力先を増やさない。重ねる物（`minSeverity` / `enrich` / `tee` / `fallback`）は
同じ型なので、そのまま繋がる。

**`Logfx.Value` を自前で持つ。** 利用側の JSON の型を借りると依存の向きが逆になり、切り出せなく
なる（実際、切り出す前は GraphQL の `Value` を借りていた）。もう 1 つは、標準の `Util.Json.Json` は
数を `BigDecimal` 1 つで持つので整数と小数を区別できず、`12` が `12.0` として出てしまう。

**トップレベルに一般名を置かない。** Flix はモジュールを隠せないので、`Log` や `Value` を
トップレベルに置くと利用側と衝突する。すべて `Logfx` の下にある。

**壊れた値は壊れたまま見せる。** `NaN` と `Infinity` は `0` ではなく `null`。`Fields.int` は
`Int32` に丸めずに `Int64` のまま持つ。静かに `2147483647` と読める数の方が、欠けている数より悪い。

## アーカイブする条件

これは非公開のリポジトリで作っている Flix 製のヘッドレス CMS から切り出した物。
そのプロジェクトが logfx を使わなくなったら、このリポジトリは
アーカイブして README の 1 行目にそう書く。その時点の版はそのまま動く（Maven 依存の無い
ソースのパッケージで、Flix の release に固定されている）。放置されたライブラリの害は「止まっていること」より「止まって
いるか分からないこと」なので、条件を先に書いておく。

## 版の付け方

semver。Flix にはまだ慣行が無いので `0.x` の規則を明文化する:

- **`0.x` の間は minor で壊す事がある。** `0.1` から `0.2` に上げる前に release note を読む。
- **対応する Flix の版を上げる時は必ず minor 以上。** patch にはしない。
- patch は API と出る JSON を変えない修正だけ。

`Logfx` は `pub` な effect なので、handler は誰でも書ける。op を足すと自前の handler を書いた
利用者が全員壊れる。だから `enabled` は、利用者が 0 人の 0.2.0 で入れた。

## 開発

```bash
make check    # 型検査
make test     # テスト
make consume  # .fpkg を作り、捨てプロジェクトから取り込んで動かす
make examples # examples/ を今のソースに対してビルドし、テストと出力を確かめる
make doc      # GitHub Pages に出す API リファレンス
make pkg      # 配布用の .fpkg
make release  # GitHub の release に .fpkg と flix.toml を付ける
```

release の前に効くのは `make consume`。自分のテストに通る事と、パッケージとして取り込める事は
別物で、0.1.0 は手元では緑のまま、`--Xsubeffecting=lambdas` を付けない人にはコンパイルできなかった
（`Sink.silent` が純粋なラムダを `IO` の所に返していた）。**logfx は実験フラグを要求しない。**
CI は push ごとに同じ script を回し、tag を打った後は GitHub の release からも取り込んで確かめる。

`make examples` は `examples/` を開発中の版に対してコンパイルする。動かなくなった例が
「読んだ人が気づく物」ではなく「ビルドの失敗」になる。リファレンスは tag からだけ公開する。
どの release にも無い API を読んでいる、という状態を読む側から見分けられないため。

Flix コンパイラは `bin/flix` が解決する（`FLIX_JAR` を渡せばそれを使う）。

## ライセンス

Apache-2.0

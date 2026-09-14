# logfx

*日本語版はこのページの[下半分](#logfx日本語)にあります。英語版が正。*

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

## License

Apache-2.0

---

# logfx（日本語）

Flix の構造化ログ。`Logfx` effect で 1 行を出し、出力先（Sink）は値として差し替える。
JDK より外の依存は無い。

> 上の英語版が正。ずれていたらそちらを見る。

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

## 入れる

`flix.toml` の `[dependencies]` に書く。Maven の依存は無いので、利用側で足す物は無い。

```toml
[dependencies]
"github:ababup1192/logfx" = { version = "0.2.0", security = "unrestricted" }
```

`security = "unrestricted"` が要るのは、`Logfx.exception` が `java.lang.Throwable`
（クラス名・message・cause の連鎖・stack frame）を触るため。版だけを書く短い形
（`= "0.2.0"`）だと Flix が取り込みを断る。

## 持っている物

| | |
|---|---|
| `Logfx` | effect。op は `emit` と `enabled` の 2 つ |
| `Logfx.trace` … `Logfx.fatal` | 1 行出す。fields は最後（パイプで受ける） |
| `Logfx.traceWith` … `Logfx.fatalWith` | 同じだが、その段が有効な時だけ fields を組み立てる |
| `Logfx.Fields` | フィールドのビルダー。`str` / `int`（`Int64`）/ `float` / `bool` / `strs` / `obj` / `opt` / `value` / `merge` |
| `Logfx.withFields` | 入れ子の文脈（span）。中で出る行すべてにフィールドが付く |
| `Logfx.exception` | `Throwable` から `exception.type` / `.message` / `.cause` / `.stacktrace` |
| `Logfx.Sink` | `Record -> Unit \ IO`。**値なので利用側が差せる**。`json` / `silent` / `collect` と、重ねる `minSeverity` / `enrich` / `tee` / `fallback` |
| `Logfx.runWith`, `Logfx.runWithMin` | 本番の handler。`runWithMin` は段より軽い行を落とす |
| `Logfx.runWithList` | **テスト用の handler。** 出た行を `List[Record]` で受け取る |
| `Logfx.Value` | フィールドに入る値。JSON と同じ形 |

キーの名前は OpenTelemetry の意味づけ規約（`http.request.method`、
`http.response.status_code`、`exception.type` …）に合わせてある。Loki や Grafana で
そのまま数えられる。

## 段の絞り方が 2 つある理由

```flix
// handler で絞る。enabled が false を返すので、infoWith は Map を組み立てない。
Logfx.runWithMin(Logfx.Severity.Warn, sink, () ->
    Logfx.infoWith("expensive", () -> Logfx.Fields.empty() |> Logfx.Fields.str("body", render()))
)

// Sink で絞る。Record は組み上がってから捨てられる。tee の片側だけ段を変えたい時に使う。
Logfx.runWith(Logfx.Sink.tee(everything, Logfx.Sink.minSeverity(Logfx.Severity.Error, alerts)), thunk)
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

## ログをテストする

```flix
let (result, lines) = Logfx.runWithList(() -> handleRequest(req));
```

`runWithList` は純粋（`IO` が付かない）で、全段を有効にする。本番の段の設定にテストが
引きずられない。

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
make check   # 型検査
make test    # テスト
make consume # .fpkg を作り、捨てプロジェクトから取り込んで動かす
make pkg     # 配布用の .fpkg
make release # GitHub の release に .fpkg と flix.toml を付ける
```

release の前に効くのは `make consume`。自分のテストに通る事と、パッケージとして取り込める事は
別物で、0.1.0 は手元では緑のまま、`--Xsubeffecting=lambdas` を付けない人にはコンパイルできなかった
（`Sink.silent` が純粋なラムダを `IO` の所に返していた）。**logfx は実験フラグを要求しない。**
CI は push ごとに同じ script を回し、tag を打った後は GitHub の release からも取り込んで確かめる。

Flix コンパイラは `bin/flix` が解決する（`FLIX_JAR` を渡せばそれを使う）。

## ライセンス

Apache-2.0

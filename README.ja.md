# logfx

Flix の構造化ログ。`Logfx` effect で 1 行を出し、出力先（Sink）は値として差し替える。
JDK より外の依存は無い。

> 英語版の [README.md](README.md) が正。ずれていたらそちらを見る。

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

## 範囲と、やらない事

これは [flix_graphql_hello](https://github.com/ababup1192/flix_graphql_hello)（Flix 製のヘッド
レス CMS）から切り出した物で、**そのプロジェクトが必要とする範囲でのみ**、1 人が空き時間に
保守する。

- **機能追加の要望は受け付けない。** バグ報告と PR は歓迎する。
- **対応する Flix の版は 1 つだけ**（`flix.toml` の物。今は 0.75.3）。上流が壊れたら追随するが、
  時期は約束しない。
- **返信に数週間かかることがある。** それが普通の状態で、放置ではない。
- **出力先（ファイル・syslog・Loki・OTLP）をここに足さない。** `Sink` は 1 行の関数型なので、
  使う場所で書く。
- **大域のロガーも設定ファイルもログの回転も持たない。** handler が設定そのもの。

### アーカイブする条件

flix_graphql_hello が logfx を使わなくなったら、このリポジトリはアーカイブして README の
1 行目にそう書く。その時点の版はそのまま動く（Maven 依存の無いソースのパッケージで、Flix の
release に固定されている）。放置されたライブラリの害は「止まっていること」より「止まって
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

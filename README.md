# logfx

Flix の構造化ログ。`Logfx` effect で 1 行を出し、出力先（Sink）は値として差し替える。
JDK より外の依存は無い。

```flix
import java.lang.System

let sink = Logfx.Sink.json(_ -> System.currentTimeMillis(), line -> println(line));

Logfx.runWith(sink, () -> {
    Logfx.Fields.empty()
        |> Logfx.Fields.str("http.method", "GET")
        |> Logfx.Fields.int("http.status_code", 200i64)
        |> Logfx.info("request finished")
})
```

```json
{"time":"2026-09-14T07:00:00.000Z","severity":"INFO","message":"request finished","http.method":"GET","http.status_code":200}
```

## 入れる

`flix.toml` の `[dependencies]` に書く。Maven の依存は無いので、利用側で足す物は無い。

```toml
[dependencies]
"github:ababup1192/logfx" = { version = "0.1.0", security = "unrestricted" }
```

`security = "unrestricted"` が要るのは、`exception` が `java.lang.Throwable` を触るため。
版だけを書く短い形（`= "0.1.0"`）だと Flix が取り込みを断る。

## 持っている物

| | |
|---|---|
| `Logfx` | effect。`trace` / `debug` / `info` / `warn` / `error` / `fatal` |
| `Logfx.Fields` | フィールドのビルダー。`str` / `int`（`Int64`）/ `bool` / `strs` / `opt` / `merge` をパイプで繋ぐ |
| `Logfx.Sink` | `Record -> Unit \ IO`。**値なので利用側が差せる**。`json` / `silent` / `collect` と、重ねる `minSeverity` / `enrich` |
| `Logfx.withFields` | 入れ子の文脈。中で出る行すべてにフィールドが付く |
| `Logfx.exception` | `Throwable` から `exception.type` / `.message` / `.stacktrace` を作る（cause を辿る） |
| `Logfx.runWith` | 本番の handler |
| `Logfx.runWithList` | **テスト用の handler。** 出た行を `List[Record]` で受け取る |
| `Logfx.Value` | フィールドに入る値。JSON と同じ形 |

キーの名前は OpenTelemetry の意味づけ規約（`http.method`、`http.status_code`、`exception.type` …）に
合わせてある。Loki や Grafana でそのまま数えられる。

## 設計

**Sink は値。** ファイルに書く・別の場所へ送る・テストで溜める、はすべて利用側で書ける。
ライブラリ側に出力先を増やさない。重ねる物（`minSeverity` で段を絞る、`enrich` で共通の
フィールドを足す）も同じ型なので、そのまま繋がる。

**`runWithList` がある。** ログはテストできる。「この操作でこの行が出る」を表駆動で書ける。

**`Logfx.Value` を自前で持つ。** 利用側の JSON の型を借りると依存の向きが逆になり、切り出せなくなる。
変換は利用側の境界で書く。

**トップレベルに一般名を置かない。** Flix はモジュールを隠せないので、`Log` や `Value` を
トップレベルに置くと利用側と衝突する。すべて `Logfx` の下にある。

## 開発

```bash
make check   # 型検査
make test    # テスト
make pkg     # 配布用の .fpkg
make release # GitHub の release に .fpkg と flix.toml を付ける
```

Flix コンパイラは `bin/flix` が解決する（`FLIX_JAR` を渡せばそれを使う）。

## ライセンス

Apache-2.0

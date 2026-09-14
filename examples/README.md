# examples

logfx を取り込んだ側から書いたコード。どれも `make examples`（`ci/example.sh`）が、
今のソースから作った `.fpkg` に対してビルドして走らせる。

| | |
|---|---|
| [`quickstart`](quickstart) | README の最初のコード片そのもの。1 行出すまで |
| [`server`](server) | サーバへの組み込み。Sink の合成・LOG_LEVEL・span・`Logfx.exception`・リクエストごとの `spawn`、そして `runWithList` によるログのテスト |

各 example は `verify.sh` を持っていて、実際に出た行を見る。

## 動かす

```bash
make examples          # 全部（.fpkg のビルドから）
```

手元で 1 つだけ触るなら、`flix.toml` が指している版（release 済みの版）がそのまま降りてくる:

```bash
cd examples/server
flix run
LOG_LEVEL=debug flix run    # routing の行が増える
flix test
```

## 決まり

- **`examples/*/flix.toml` の logfx の版は、ルートの `flix.toml` の版と一致させる。**
  ずれていると `ci/example.sh` が止まる。版を上げたら examples も上げる
- **依存はパスで書かない。** Flix の依存は `github:` しか書けないので、パスに逃がすと
  利用者が実際に書く物と違う物を確かめる事になる。`ci/example.sh` は `lib/` に
  今の `.fpkg` を先回りで置いて、宣言はそのままにする
- 書き方（`mod` の名前、`\ {IO, Logfx}`、テストの形）は
  [nextcms](../AGENTS.md#出自) に合わせる。logfx の唯一の利用者がそう書いているため

# logfx

Flix の構造化ログのライブラリ。`Logfx` effect で 1 行を出し、出力先（Sink）は値として差し替える。

このファイルは**毎回読まれる索引**なので、置くのは「破ると事故る決まり」と「どこを見るか」だけ。
使い方は [README.md](README.md)、Flix の書き方は `docs/flix-conventions.md` に書く。

## 会話ポリシー

日本語で会話してください。途中報告なども含めて、日本語で回答してください。

単語は業界の言葉をそのまま使う（カタカナ・英語のまま。和語へ言い換えない・造語を作らない）。
説明は平易に書く。独自の比喩で名付けない。

**ただし README と、外に出る文字列（エラーメッセージを含む）は英語。**
Flix のエコシステムは小さく、読者を日本語話者に絞ると次の書き手が現れる確率が下がる。

## 出自

nextcms（Flix 製のヘッドレス CMS。非公開のリポジトリなのでリンクは張らない）の
`src/log/` から 2026-09-14 に切り出した。
本体はこのライブラリを `flix.toml` の `[dependencies]` で取り込んでいて、**写しは持っていない**。
つまりここを直すと、版を上げてリリースしてから本体の `flix.toml` を上げる往復が要る。

## Flix のお約束

- **Flix を書く前・テストを書く前に `/flix-docs` を引く**（本文は `.claude/skills/flix-docs/SKILL.md`）
- **コンパイルエラーが出たら `/compile-fix`**（本文は `.claude/skills/compile-fix/SKILL.md`）
- 予約語・コメントの流儀・型の設計の本文: [docs/flix-conventions.md](docs/flix-conventions.md)

## 破ると事故る決まり

- **トップレベルに名前を置かない。** Flix はモジュールを隠せないので、`Log` や `Value` を
  トップレベルに置くと利用側と必ず衝突して、そのライブラリが使えなくなる。**全部 `Logfx` の下**に置く
- **Maven の依存を増やさない。** Flix は利用側の `flix.toml` に Maven の依存を書かせる。
  増やすと利用者が版を合わせる義務を負い、ずれても止められない。今はゼロ
- **Java interop を増やす時は影響を考える。** 利用側は `security = "unrestricted"` を書かないと
  取り込めない。今は `Logfx.exception` の `java.lang.Throwable` だけがその理由
- **`pub eff Logfx` の op を増やさない。** handler は誰でも書けるので、op を足すと自分で
  handler を書いた利用者が全員壊れる。op は `emit` と `enabled` の 2 つで確定。
  それでも増やすなら、`0.x` の間は minor、`1.0` 以降は major を上げる
- **`Sink` は `Record -> Unit \ IO` の型 alias のまま。** opaque な enum にすると、利用者が
  自分の `def` をそのまま渡せなくなる
- **パッケージ名とトップレベルの mod 名を一致させる**（`logfx` → `Logfx`）
- **版は `flix.toml` の `[package] version` と release の tag（`v<version>`）を必ず揃える。**
  Flix は tag から `.fpkg` を取るので、ずれると利用側の解決が失敗する
- **実験フラグ（`--Xsubeffecting=lambdas` など）込みでしか通らないコードを書かない。**
  利用側は素の flix で取り込む。純粋なラムダを `\ IO` の所に渡す時は `checked_ecast` を書く
- **release の前に `make consume` を通す。** 型検査とテストが緑でも取り込めない事がある

## コーディングポリシー

コードには **How** / テストコードには **What** / コミットログには **Why** / コードコメントには **WhyNot**

特にコードコメントは WhyNot を重視し、How・What を書かない。実装の由来や旧実装などの歴史背景も書かない。

**理由を正確に書く。** ライブラリは理由ごと真似られるので、間違った理由は API そのものより害が大きい。

## ビルドと配布

Flix コンパイラは `bin/flix` が解決する（`FLIX_JAR` か `FLIX_ENGINE_ROOT` を渡せばそれを使う）。

```bash
make check    # 型検査
make test     # テスト
make consume  # まっさらなプロジェクトから取り込んで動かす（ci/consume.sh local）
make pkg      # 配布用の .fpkg（build/logfx/artifact/）
make release  # GitHub の release に .fpkg と flix.toml を付ける
```

`bin/flix` は `bin/with-lock` で順番待ちになる（同じ機械で 2 つの Flix コンパイラを同時に
動かすと、1 本 3 GB のメモリを取り合って GC で遅くなるか OOM で落ちる）。**待たされるのは正常**で、
`pkill` や `FLIX_NO_LOCK` で割り込まない（`FLIX_NO_LOCK` を使うのは、job が 1 本ずつ走り
`/usr/bin/shlock` も無い CI の runner だけ）。

## ディレクトリ

| 場所 | 中身 |
|---|---|
| `src/Logfx.flix` | effect の宣言、6 段の関数（`log` / `logWith` 経由）、`Value` と JSON 化、`runWith` / `runWithMin` / `runWithList`、`withFields`、`exception` |
| `src/Logfx/Fields.flix` | フィールドのビルダー |
| `src/Logfx/Sink.flix` | Sink（`json` / `silent` / `collect` と、重ねる `minSeverity` / `enrich` / `tee` / `fallback`） |
| `test/TestLogfx.flix` | 表駆動のテスト |
| `ci/` | 取り込み側から見る smoke（`consume.sh` と、捨てプロジェクトの `consumer/`） |
| `.github/workflows/ci.yml` | push ごとの `make check` / `make test` と取り込みの確認 |

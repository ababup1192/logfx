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
つまりここを直すと、バージョンを上げてリリースしてから本体の `flix.toml` を上げる往復が要る。

## Flix のお約束

- **Flix を書く前・テストを書く前に `/flix-docs` を引く**（本文は `.claude/skills/flix-docs/SKILL.md`）
- **コンパイルエラーが出たら `/compile-fix`**（本文は `.claude/skills/compile-fix/SKILL.md`）
- 予約語・コメントの流儀・型の設計の本文: [docs/flix-conventions.md](docs/flix-conventions.md)

## 破ると事故る決まり

- **トップレベルに名前を置かない。** Flix はモジュールを隠せないので、`Log` や `Value` を
  トップレベルに置くと利用側と必ず衝突して、そのライブラリが使えなくなる。**全部 `Logfx` の下**に置く
- **Maven の依存を増やさない。** Flix は利用側の `flix.toml` に Maven の依存を書かせる。
  増やすと利用者がバージョンを合わせる義務を負い、ずれても止められない。今はゼロ
- **Java interop を増やす時は影響を考える。** 利用側は `security = "unrestricted"` を書かないと
  取り込めない。今は `Logfx.exception` の `java.lang.Throwable` だけがその理由
- **`pub eff Logfx` の op を増やさない。** handler は誰でも書けるので、op を足すと自分で
  handler を書いた利用者が全員壊れる。op は `emit` と `enabled` の 2 つで確定。
  それでも増やすなら、`0.x` の間は minor、`1.0` 以降は major を上げる
- **`Sink` は `Record -> Unit \ IO` の型 alias のまま。** opaque な enum にすると、利用者が
  自分の `def` をそのまま渡せなくなる
- **パッケージ名とトップレベルの mod 名を一致させる**（`logfx` → `Logfx`）
- **`flix.toml` の `[package] version` と release の tag（`v<version>`）を必ず揃える。**
  Flix は tag から `.fpkg` を取るので、ずれると利用側の解決が失敗する
- **実験フラグ（`--Xsubeffecting=lambdas` など）込みでしか通らないコードを書かない。**
  利用側は素の flix で取り込む。純粋なラムダを `\ IO` の所に渡す時は `checked_ecast` を書く
- **release の前に `make consume` を通す。** 型検査とテストが緑でも取り込めない事がある
- **`docs/release-notes/v<version>.md` を書いてから release する**（無いと `make release` が止まる）。
  README が「`0.x` の minor は release note を読め」と書いているので、読む物が要る
- **push してから `make release`。** tag はリモートの HEAD に付くので、未 push のコミットがあると
  バージョンだけ進んだ release ができる（0.2.1 で実際に踏んだ）
- **バージョンを上げたら `examples/*/flix.toml` の logfx のバージョンも上げる。** ずれていると `ci/example.sh`
  が止まる（例が、どの release にも無い API を指したままになる為）
- **README の最初のコード片は `examples/quickstart` の写し。** 直す時は両方。
  あちらが本体で、README のコードは誰もコンパイルしない

## コーディングポリシー

コードには **How** / テストコードには **What** / コミットログには **Why** / コードコメントには **WhyNot**

特にコードコメントは WhyNot を重視し、How・What を書かない。実装の由来や旧実装などの歴史背景も書かない。

**理由を正確に書く。** ライブラリは理由ごと真似られるので、間違った理由は API そのものより害が大きい。

**日本語を書くのは README の下半分と、AGENTS.md・`docs/`・`.claude/` だけ。** コード・テスト・
examples・`ci/`・`bin/`・Makefile・workflow のコメントと文字列は英語。読者を日本語話者に絞らない。

**造語・比喩を使わない。** 言い換えの表は [scripts/jargon-denylist.txt](scripts/jargon-denylist.txt)
（nextcms から持ってきた）で、`make check-jargon` が見張る。その語でしか書けない所が出たら、
表の 3 列目の除外に足して理由を残す。

**`///`（doc コメント）は英語、`//` は日本語。** `flix doc` の出力が
[公開リファレンス](https://ababup1192.github.io/logfx/Logfx.html)になるので、`///` は外に出る文字列。
`///` の中の WhyNot も英語で書く。

## ビルドと配布

Flix コンパイラは `bin/flix` が解決する（`FLIX_JAR` か `FLIX_ENGINE_ROOT` を渡せばそれを使う）。

```bash
make check        # 型検査
make check-jargon # 日本語に、言い換え先のある語が残っていないか（scripts/check-jargon.sh）
make test         # テスト
make consume      # まっさらなプロジェクトから取り込んで動かす（ci/consume.sh local）
make examples     # examples/ を今のソースに対してビルドして走らせる（ci/example.sh）
make doc          # 公開する API リファレンス（ci/doc.sh → build/doc/）
make pkg          # 配布用の .fpkg（build/logfx/artifact/）
make release      # GitHub の release に .fpkg と flix.toml を付ける
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
| `examples/` | 利用側から書いたコード。`quickstart`（README の最初の塊）と `server`（組み込み一式） |
| `docs/release-notes/` | バージョンごとの release note（`make release` が `--notes-file` で使う） |
| `scripts/` | 日本語の言い換えの表と、それを見張る `check-jargon.sh` |
| `ci/` | 取り込み側から見る smoke（`consume.sh` と捨てプロジェクトの `consumer/`）、`example.sh`、リファレンスの `doc.sh` |
| `.github/workflows/ci.yml` | push ごとの `make check` / `make test` / 取り込み / `make examples` |
| `.github/workflows/pages.yml` | tag を打った時だけ、`make doc` の結果を GitHub Pages に置く |

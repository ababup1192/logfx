# Flix を書くときの決まり

## 予約語を識別子に使わない

**全量は engine リポ（flix_game_engine）の `bin/lint-rules/flix-reserved.json` が source of truth**
（0.75.1 で実測した 43 語。このリポジトリには無い）。
よく踏むのは `from` / `into` / `run` / `spawn` / `region` / `project` / `solve` / `inject` /
`handler` / `query` / `select` / `where` / `force` / `discard`。

変数・関数名だけでなく**レコードのフィールド名**でも落ちる（`{ spawn = ... }` は不可）。
エラーは `Expected ',' before '='` のような間接的なパースエラーで出るので、原因に見えない。

**型検査が終わらないときも、まずこれを疑う。** Flix はパースで止まらず、壊れた構文木の
まま型検査へ進んで発散することがある — 赤も警告も出ず、ただ何分でも回り続ける
（2026-08-19 に `{ into = …, from = … }` で 6 時間溶かした）。
engine リポでは `bin/fge flix-reserved <ファイル…>`（全量は `--all`）が保存時とコミット時に自動で走る
（このリポジトリに `bin/fge` は無いので、目視で避ける）。
ゲームで踏みやすいのは `spawn`（湧き位置 → `start`）、`run`（走り → `walkR` 等)、
`project`（→ `apply`）、グラデーションの両端の `from` / `to`（→ `top` / `bottom`。
engine の `Render.vgrad` も同じ理由で `{ top, bottom }`）。

## コメントの流儀

- コードには **How**
- テストコードには **What**
- コミットログには **Why**
- コードコメントには **WhyNot**

How と What をコメントに書かない。実装の由来・旧実装・移行史も書かない。
独自の比喩を使わない（「局面」「店」ではなく、フェーズ・Map のような直接表現）。

**単語は業界の言葉をそのまま使う。** ゲーム業界・ソフトウェア業界で通じる語を優先し、
カタカナ（和製英語）か英語のまま書く（レイヤー・バージョン・ボタン・キャッシュ・
`Layer` `Version`）。和語へ言い換えず、造語も作らない。読み手はエンジニア。

**説明は平易に。** 難しい数学用語・専門用語に寄りかからず、何が起きるのかを普通の
言葉で書く（「線形補間する」ではなく「2 つの値の間をなめらかにつなぐ」）。

## 名前の付け方（モジュール・関数・変数）

**英語にすれば安全、ではない。** `bless` `carve` のように、英単語でも
このリポジトリだけの意味を持たせると、初めて読む人にも海外の人にも通じない。
上の言葉づかいの決まりは、そのまま識別子にも当てはまる。

### 1. 同じ物を指す言葉が業界にあるなら、それを使う

探す順番:

1. **ゲーム業界の語** — `sprite` `tilemap` `viewport` `hitbox` `atlas` `tween`
2. **ソフトウェア一般の語** — `cache` `buffer` `snapshot` `pipeline` `handler` `registry`
3. **他のゲームエンジンが同じ物をどう呼んでいるか** — Unity / Unreal / Godot / Bevy。
   同じ物に別の名前を付けない（このエンジンは Bevy の render-from-World の考え方に
   そろえているので、迷ったら Bevy の語を見る）

3 つとも当てはまらない物にだけ、説明的な名前を組み立てる（`silhouettePng` のように、
読んで何をする物か分かる形）。**比喩で名付けない。**

### 2. 動詞は大手の命名規則に合わせる

| 動詞 | 意味 |
|---|---|
| `get*` | 取り出すだけ（安い・失敗しない） |
| `load*` / `fetch*` | 外から取ってくる（遅い・失敗しうる） |
| `build*` / `make*` / `compute*` | 計算して作る |
| `is*` / `has*` / `can*` | Bool を返す |
| `set*` / `with*` | 値を差し替える（`with*` は元を変えず新しい値を返す） |
| `to*` / `as*` | 型を変える（`to*` は作り直す・`as*` は見方を変えるだけ） |

**1 つの動詞に 2 つの意味を持たせない。** `get` が実は読み込みに行く、のような名前は
呼ぶ側が値段を読み違える。

### 3. 迷ったときの決め方

その名前を英語で読んだ人に意味が通るか。通らないなら、業界の語をもう一度探す。

## 型の設計（データの持ち方）

- **取りうる値が決まっている物（状態・モード・種別）は String で持たない。enum にする。**
  文字列の等値で分岐すると網羅性チェックが効かない。Doc(JSON) から来る String は、
  読み込む所で 1 回だけ enum へ変換して内側は enum で回す
- **その case だけが使う値は、レコードに平らに並べず enum の payload へ入れる。**
  並べると、どのフィールドがどの case の物か型から読めなくなる。
  どの case でも使う値はレコード側に残す
  - payload にレコードは置けない（下の `Eq` の注意）。値が 2 つ以上要るときは
    case へ並べるか、`Eq` を derive した別の enum で包む

詳しくと例は `.claude/skills/flix-docs/SKILL.md` の「型の設計」。

## 二乗を書かない

N はゲームが決める。エンジンは N を知らない（今のテンプレが 9 要素だから軽い、は
エンジンの性質ではない）。次の 5 つは、実害が見えなくても書かない。

- **`List.foldLeft` の中で蓄積を `List.append` の第 1 引数に置かない。**
  `::` で先頭へ積んで、最後に `List.reverse`（手本は `Text.groupRows`）。
  名前が `acc` でなくても、タプルを分解した別名でも同じ
- **文字列も同じ。1 文字ずつ足して伸ばさない。** `foldLeft(String.concat, "")` も
  `"${acc}${ch}"` も、1 回ごとに全体を作り直すので文字数の二乗になる。
  `List[Char]` を `::` で積んで、最後に region + `StringBuilder` で 1 回だけ組む:
  ```flix
  region rc {
      let sb = StringBuilder.empty(rc);
      List.forEach(ch -> StringBuilder.append(ch, sb), chars);
      StringBuilder.toString(sb)
  }
  ```
- **ループの中で `List.exists` / `List.memberOf` を呼ばない。** 会員判定は `Set` / `Map`。
  順序も要るなら「順序つきの蓄積 + 判定用の `Set`」の二本立て
- **`List.range` を回して `List.nth` で引かない。** 1 巡で済ませる
  （`List.zip` は短い方で打ち切るので、余った側の後始末が要るなら先に長さをそろえる）
- **`List.sortBy` のキーに重い関数を渡さない。** `sortBy` は
  `sortWith(Order.compare `on` f)` なので、**1 回の比較でキー関数を 2 回呼ぶ**。
  先に `(キー, 要素)` を作って `sortBy(fst)` で並べ、最後に戻す。
  キー列が同じなら並びはビット同一になるので、この置き換えで絵は変わらない

機械で裁く lint は無い。基準・測り方・残っている二乗の一覧は engine リポの
`docs/performance.md`。

## effect の和の書き方

alias とドメインの署名は `+` 形（`Db + CmsErr + Tenant`）、`run` の引き算と多相の集合リテラルは `{}` 形（`ef - {Db, CmsErr}`、`Route[{Graphql, ef}]`）。
`DbRead` は `DbErr` を含むので `DbRead + DbErr` と書かない。

## JVM の例外の網（try / catch）は handler の入れ子を見て置く

Flix 0.75.3 では、`try / catch` が拾えるかどうかが `run … with handler` との位置関係で決まる（2026-09-08 に実測。表は `test/app/TestJvmCatchNesting.flix`）。

| 形 | 拾えるか |
|---|---|
| `try { run { op; throw } }`（handler が try の内側。何段でも） | 拾える |
| `run { try { op; throw } }`（try の直下から外の handler へ op。間に run 無し） | 拾える（`Db.guard` の形） |
| `run { try { run { op }; throw } }`（外へ op を通した run を抜けてから throw） | 拾える |
| `run { try { run { op; throw } } }`（外へ op を通した run の**中**で throw） | **素通り** |
| `run { try { op } } with handler { def op = throw }`（handler の本体が投げ、handler は try の外） | **素通り** |

素通りした例外は、その handler より外側にある catch（`HttpServer.respond` など）か、スレッドの先頭まで飛ぶ。
網を置く時は次のどちらかにする:

- **handler を try の内側に入れる**（`BackgroundJobs.guarded` が Logfx を sink で入れ直す形）
- **一番内側の handler の直下に try を置き、その中に run を置かない**（`Db.guard`、`BackgroundJobs.guardedPart`）

catch の腕には effect の op を書かない（JVM の VerifyError）。腕は値を返すだけにして、ログや raise は catch を抜けてから。

## GraphQL のリゾルバのラムダに effect を使う式を直に書かない

Flix 0.75.3 は、リゾルバのラムダの中に effect（`Time.Clock.Clock` など）を呼ぶ式を直に書くと、
JVM の **VerifyError（`Instruction type does not match stack map`）** を出すコードを吐く事がある。
**effect を使う計算は名前付きの関数に切り出し、ラムダからはそれを呼ぶだけにする**
（実例は `src/admin/ScheduleResolvers.flix` の `isOverdue`）。

```flix
// NG: ラムダの中で直に Clock を呼ぶ
overdue = (_context, source) -> Ok(source#status == ScheduleStatus.Pending and Timestamp.toEpochMillis(source#runAt) <= Time.Clock.now()),

// OK: 関数に切り出す
overdue = (_context, source) -> Ok(isOverdue(source)),
```

**いつ出るか**（2026-09-07 に実測）:

| どこ | 出るか |
|---|---|
| `make check`（型検査） | 出ない |
| スキーマの組み立て（`AdminSchema.make` + `Graphql.buildEngine`） | 出ない |
| そのフィールドを**選ばない** query | 出ない |
| そのフィールドを**選ぶ** query | **出る** |

つまり、GraphQL 越しに 1 度も選ばれないフィールドは、誰も見張っていない。
しかも実行中に例外で飛ぶので Tx が開いたまま接続が漏れ、後続のテストが DROP TABLE で止まる。

**見張るテスト**:

- `test/admin/TestApiSurface.flix` — 管理 API と Account API の object 型とフィールドの一覧を
  introspection で読んで突き合わせる（DB 不要。`make test` に載る）。型やフィールドを足すとここが落ちる
- `test/Pg/TestAdminMutationsPg.flix` — admin.graphql の全フィールドを GraphQL 越しに 1 度は選ぶ
- `test/Pg/TestAccountPg.flix` / `test/Pg/TestPersonalTokenPg.flix` — Account API の同じ物
- `test/Pg/TestAssetsPg.flix` の `testPgAssetInContentApi` — コンテンツ API の組み込みフィールド

フィールドを足したら、`TestApiSurface` の期待値と、上の Pg テストの selection の**両方**に足す。

## GraphQL のリゾルバは既定に足す形で書く

schemagen は object 型ごとに **既定リゾルバ** `<型名>Defaults()` を生成する。
中身は「source の同名ラベルをそのまま返す」だけで、対象は**素通しにできるフィールド**
（引数が無く、スカラーか enum かそのリストを返す物）。source の型は行変数で開けてあるので、
SDL に無いラベル（`publicId` など）をドメインの型が持っていてもよい。

手書きのリゾルバは**写しが要るフィールドだけ**を書き、残りは既定に任せる。

```flix
pub def resolvers(): GeneratedAdmin.WebhookResolvers[AdminEff] =
    {
        id        = (_context, source) -> Ok(AdminMapping.idOfPublic(source#publicId)),
        events    = (_context, source) -> Ok(source#events |> List.map(AdminMapping.webhookEventToGql)),
        createdAt = (_context, source) -> Ok(Timestamp.toIso8601(source#createdAt))
        | GeneratedAdmin.webhookDefaults()
    }
```

- `名前 = ...` は**レコードの更新**。既定にあるフィールドを差し替える（Flix の更新は型も変えられる）。
  `ID`・`DateTime`・enum は既定の型（`Id` / `String` / GraphQL の enum）とドメインの型が違うので、
  ここで `AdminMapping.idOfPublic` / `Timestamp.toIso8601` / `AdminMapping.xxxToGql` を通す
- `+名前 = ...` は**レコードの拡張**。既定に無いフィールド（オブジェクト型を返す物・引数を持つ物）に使う。
  同じフィールドに `+` を使うとラベルが重複して `XxxResolvers[ef]` と一致しない
- 既定のフィールドを 1 つも残さないなら、既定を使わず全部書く（`| ...Defaults()` が飾りになる）

**書き忘れは型検査で落ちる。** SDL にフィールドを足すと既定リゾルバに `Ok(src#新しい名前)` が増え、
ドメインの型に同名のラベルが無ければ `XxxResolvers[ef]` と一致せず、そのフィールドだけ
`{ 新しい名前 = String | r1 }` の形が残った型で `Type Error [E6794]` が出る。

雛形は `make scaffold TYPE=Xxx` が既定を使う形で吐く（`DEFAULTS=no` で全フィールド）。

## HTTP のルートは表に 1 行

ルーティングは `src/app/Server.flix` の `routes` の表（`Router.route(メソッド, "/パス", engine, handler)`）で持つ。
文字列の分岐や `Main` のエンジン選択に書き足さない。

- **表に 1 行**足す。`engine` は要る GraphQL エンジン（`Engine.Content` / `Admin` / `Account`）か、要らなければ `None`。
  Main が表の `engine` を見てエンジンを入れるので、Main は触らない
- **`test/app/TestServer.flix` の `testServerRoutesDescribe` の期待値に 1 行**足す（`/p/{projectSlug}/` 付きの複製も出る。Account だけ複製されない）
- `/p/{projectSlug}/...` は表に書かない（`Router.withProjectPrefix` が複製する）。パスの `{name}` は `routeRequest#params` に生の文字列で入るので、
  型付きの id は handler の入口で `ProjectSlug.parse` などの既存の parse を呼ぶ
- OPTIONS の 204 と 405 の `Allow` は表から出る。手で列挙しない
- 行の handler は自分の effect（`Graphql` だけ、`Health[ef]` の `ef` だけ）を宣言し、表に載せる時に `widen` で表全体の effect に広げる。死活の値（DB に届くか・ワーカーのまとめ・接続数）は effect でなく `Health[ef]`（関数のレコード）で `routes` に渡す
- `handler` は Flix の予約語。レコードのフィールドも変数も `handle` / `pipeline` にする

## その他の注意

- レコードは `Eq` / `Order` を持てない。比較したい値は名前付き 1 フィールドの enum で包む
- `forM` は効果の逐次実行には使えない
- 小数は Float64 で書く（`1.0` は Float64。Float32 のリテラルには `f32` サフィックスが要る）。
  engine の pub 面に Float32 は出さない決まりで、Float32 は GL / OpenAL / STB を呼ぶ
  境界の内側だけ（engine のリポジトリでは `make lint-f32` が検査する）

## 迷ったら引く

- 構文・パイプスタイル・エフェクト・テストの書き方: `.claude/skills/flix-docs/SKILL.md`
- コンパイルエラーが出た: `.claude/skills/compile-fix/SKILL.md`
- テストを設計する: engine リポの `.claude/skills/quality-assurance/SKILL.md`（このリポジトリには無い）

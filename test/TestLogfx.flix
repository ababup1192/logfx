///
/// Log: 1 行 JSON の形（toJsonLine）、Fields のビルダー、span（withFields）、Sink の合成、Java の例外の写し（exception）。
///
mod TestLogfx {
    import java.lang.ArithmeticException
    import java.lang.IllegalStateException
    import java.lang.RuntimeException
    import java.lang.Throwable
    import java.lang.VerifyError

    use Logfx.Severity
    use Logfx.Fields

    ///
    /// 比べやすいように Record を (severity, message, fields の一覧) にする。
    ///
    def toTuple(record: Logfx.Record): (Severity, String, List[(String, Logfx.Value)]) =
        (record#severity, record#message, Map.toList(record#fields))

    ///
    /// severity と message と fields から Record を作る。
    ///
    def recordOf(severity: Severity, message: String, fields: Fields): Logfx.Record =
        { severity = severity, message = message, fields = fields }

    // ---- toJsonLine ----

    /// キーの順は time / severity / message が先頭で、残りは名前順。severity は小文字。数・真偽・一覧はその型のまま出る。
    @Test
    def testToJsonLineTable(): Unit \ Assert =
        let cases = List#{
            ((0i64, recordOf(Severity.Info, "hello", Fields.empty())),
             "{\"time\":\"1970-01-01T00:00:00.000Z\",\"severity\":\"info\",\"message\":\"hello\"}"),
            ((1757300000123i64, recordOf(Severity.Warn, "m", Fields.empty() |> Fields.str("n", "x") |> Fields.int("a", 12i64) |> Fields.bool("b", true) |> Fields.strs("l", List#{"p", "q"}))),
             "{\"time\":\"2025-09-08T02:53:20.123Z\",\"severity\":\"warn\",\"message\":\"m\",\"a\":12,\"b\":true,\"l\":[\"p\",\"q\"],\"n\":\"x\"}"),
            ((0i64, recordOf(Severity.Error, "e", Fields.empty())),
             "{\"time\":\"1970-01-01T00:00:00.000Z\",\"severity\":\"error\",\"message\":\"e\"}"),
            ((0i64, recordOf(Severity.Fatal, "f", Fields.empty())),
             "{\"time\":\"1970-01-01T00:00:00.000Z\",\"severity\":\"fatal\",\"message\":\"f\"}"),
            ((0i64, recordOf(Severity.Debug, "d", Fields.empty())),
             "{\"time\":\"1970-01-01T00:00:00.000Z\",\"severity\":\"debug\",\"message\":\"d\"}"),
            ((0i64, recordOf(Severity.Trace, "t", Fields.empty())),
             "{\"time\":\"1970-01-01T00:00:00.000Z\",\"severity\":\"trace\",\"message\":\"t\"}")
        };
        Assert.assertEq(expected = cases |> List.map(snd), cases |> List.map(match ((time, record), _) -> Logfx.toJsonLine(time, record)))

    /// 制御文字（改行・エスケープシーケンス）は message からも文字列のフィールドからも一覧の中からも落ちる（log injection を防ぐ）。
    @Test
    def testToJsonLineDropsControlChars(): Unit \ Assert =
        Assert.assertEq(
            expected = "{\"time\":\"1970-01-01T00:00:00.000Z\",\"severity\":\"info\",\"message\":\"ab[31m\",\"l\":[\"x\"],\"p\":\"/health{\\\"fake\\\":1}\"}",
            Logfx.toJsonLine(0i64, recordOf(Severity.Info, "a\nb[31m", Fields.empty() |> Fields.str("p", "/health\n{\"fake\":1}\r") |> Fields.strs("l", List#{"x\t"}))))

    /// 同じ key を 2 回付けると後の値が勝つ。
    @Test
    def testToJsonLineLastKeyWins(): Unit \ Assert =
        Assert.assertEq(
            expected = "{\"time\":\"1970-01-01T00:00:00.000Z\",\"severity\":\"info\",\"message\":\"m\",\"k\":\"2\"}",
            Logfx.toJsonLine(0i64, recordOf(Severity.Info, "m", Fields.empty() |> Fields.str("k", "1") |> Fields.str("k", "2"))))

    /// fields に time / severity / message があっても先頭の 3 つが勝ち、2 度は出ない。
    @Test
    def testToJsonLineHeaderKeysWin(): Unit \ Assert =
        Assert.assertEq(
            expected = "{\"time\":\"1970-01-01T00:00:00.000Z\",\"severity\":\"info\",\"message\":\"m\"}",
            Logfx.toJsonLine(0i64, recordOf(Severity.Info, "m", Fields.empty() |> Fields.str("time", "x") |> Fields.str("severity", "y") |> Fields.str("message", "z"))))

    /// time は ISO 8601 の UTC で ms 固定。0 でも .000Z、うるう日、9999 年、負の時刻（1970 年より前）も出る。
    @Test
    def testToJsonLineTimeTable(): Unit \ Assert =
        let cases = List#{
            (0i64,               "1970-01-01T00:00:00.000Z"),
            (951782400000i64,    "2000-02-29T00:00:00.000Z"),
            (1757300000123i64,   "2025-09-08T02:53:20.123Z"),
            (253402300799999i64, "9999-12-31T23:59:59.999Z"),
            (-1i64,              "1969-12-31T23:59:59.999Z")
        };
        Assert.assertEq(expected = cases |> List.map(snd), cases |> List.map(match (time, _) -> Logfx.timeText(time)))

    /// Float の NaN と Infinity は JSON に書けないので null。
    @Test
    def testToJsonLineNonFiniteIsNull(): Unit \ Assert =
        Assert.assertEq(
            expected = "{\"time\":\"1970-01-01T00:00:00.000Z\",\"severity\":\"info\",\"message\":\"m\",\"inf\":null,\"nan\":null}",
            Logfx.toJsonLine(0i64, recordOf(Severity.Info, "m", Map#{"nan" => Logfx.Value.Float(Float64.nan()), "inf" => Logfx.Value.Float(Float64.positiveInfinity())})))

    // ---- Fields ----

    /// str / int / bool / strs はその型の Logfx.Value になり、opt の None は付かず、Some は str と同じ。
    @Test
    def testFieldsTable(): Unit \ Assert =
        let cases = List#{
            (Fields.empty() |> Fields.str("k", "v"),               List#{("k", Logfx.Value.Str("v"))}),
            (Fields.empty() |> Fields.int("k", 7i64),              List#{("k", Logfx.Value.Int(7i64))}),
            (Fields.empty() |> Fields.bool("k", false),            List#{("k", Logfx.Value.Bool(false))}),
            (Fields.empty() |> Fields.strs("k", List#{"a", "b"}),  List#{("k", Logfx.Value.List(List#{Logfx.Value.Str("a"), Logfx.Value.Str("b")}))}),
            (Fields.empty() |> Fields.opt("k", None),              Nil),
            (Fields.empty() |> Fields.opt("k", Some("v")),         List#{("k", Logfx.Value.Str("v"))})
        };
        Assert.assertEq(expected = cases |> List.map(snd), cases |> List.map(match (fields, _) -> Map.toList(fields)))

    /// merge は other が勝つ（同じ key は other の値、無い key は両方残る）。
    @Test
    def testFieldsMergeOtherWins(): Unit \ Assert =
        Assert.assertEq(
            expected = List#{("a", Logfx.Value.Str("other")), ("b", Logfx.Value.Str("base")), ("c", Logfx.Value.Str("other"))},
            Fields.empty() |> Fields.str("a", "base") |> Fields.str("b", "base")
                |> Fields.merge(Fields.empty() |> Fields.str("a", "other") |> Fields.str("c", "other"))
                |> Map.toList)

    /// int は Int32 に収まらない値も丸めずに持ち、JSON にもその桁数で出る（2 GB 超のバイト数・μs の累計）。
    @Test
    def testFieldsIntKeepsInt64(): Unit \ Assert =
        let fields = Fields.empty() |> Fields.int("hi", Int64.maxValue()) |> Fields.int("lo", Int64.minValue());
        Assert.assertEq(
            expected = (List#{("hi", Logfx.Value.Int(Int64.maxValue())), ("lo", Logfx.Value.Int(Int64.minValue()))},
                        "{\"time\":\"1970-01-01T00:00:00.000Z\",\"severity\":\"info\",\"message\":\"m\",\"n\":3000000000}"),
            (Map.toList(fields), Logfx.toJsonLine(0i64, recordOf(Severity.Info, "m", Fields.empty() |> Fields.int("n", 3000000000i64)))))

    /// float / obj / value はその形の Logfx.Value になる（value は Null も入れられる）。
    @Test
    def testFieldsCoversEveryValue(): Unit \ Assert =
        let cases = List#{
            (Fields.empty() |> Fields.float("k", 1.5),                                List#{("k", Logfx.Value.Float(1.5))}),
            (Fields.empty() |> Fields.obj("k", Fields.empty() |> Fields.str("a", "b")), List#{("k", Logfx.Value.Obj(Map#{"a" => Logfx.Value.Str("b")}))}),
            (Fields.empty() |> Fields.value("k", Logfx.Value.Null),                   List#{("k", Logfx.Value.Null)})
        };
        Assert.assertEq(expected = cases |> List.map(snd), cases |> List.map(match (fields, _) -> Map.toList(fields)))

    /// valueAs* は自分の case だけを取り出し、他の case では None。valueIsNull は Null にだけ true。
    @Test
    def testValueAccessors(): Unit \ Assert =
        let str = Logfx.Value.Str("s");
        let int = Logfx.Value.Int(7i64);
        Assert.assertEq(
            expected = (Some("s"), None, Some(7i64), None, Some(1.5), Some(true), Some(List#{str}), Some(Map#{"a" => str}), (true, false)),
            (Logfx.valueAsStr(str), Logfx.valueAsStr(int), Logfx.valueAsInt(int), Logfx.valueAsInt(str),
             Logfx.valueAsFloat(Logfx.Value.Float(1.5)), Logfx.valueAsBool(Logfx.Value.Bool(true)),
             Logfx.valueAsList(Logfx.Value.List(List#{str})), Logfx.valueAsObj(Logfx.Value.Obj(Map#{"a" => str})),
             (Logfx.valueIsNull(Logfx.Value.Null), Logfx.valueIsNull(str))))

    // ---- withFields（span）----

    /// 外の fields は中の全行に付く。severity は呼んだ関数の物。
    @Test
    def testWithFieldsAttachesToAllInnerLines(): Unit \ Assert =
        let span = Fields.empty() |> Fields.str("request.id", "r1");
        let (_, records) = Logfx.runWithList(() -> Logfx.withFields(span, () -> {
            Fields.empty() |> Logfx.info("one");
            Fields.empty() |> Fields.str("k", "v") |> Logfx.warn("two")
        }));
        Assert.assertEq(
            expected = List#{
                (Severity.Info, "one", List#{("request.id", Logfx.Value.Str("r1"))}),
                (Severity.Warn, "two", List#{("k", Logfx.Value.Str("v")), ("request.id", Logfx.Value.Str("r1"))})},
            records |> List.map(toTuple))

    /// 同じ key は内側（行に近い方）が勝つ。span の入れ子も内側が勝つ。
    @Test
    def testWithFieldsInnerWins(): Unit \ Assert =
        let outer = Fields.empty() |> Fields.str("k", "outer") |> Fields.str("o", "1");
        let inner = Fields.empty() |> Fields.str("k", "inner");
        let (_, records) = Logfx.runWithList(() -> Logfx.withFields(outer, () -> Logfx.withFields(inner, () -> {
            Fields.empty() |> Logfx.info("span");
            Fields.empty() |> Fields.str("k", "line") |> Logfx.info("line")
        })));
        Assert.assertEq(
            expected = List#{
                (Severity.Info, "span", List#{("k", Logfx.Value.Str("inner")), ("o", Logfx.Value.Str("1"))}),
                (Severity.Info, "line", List#{("k", Logfx.Value.Str("line")), ("o", Logfx.Value.Str("1"))})},
            records |> List.map(toTuple))

    /// thunk を抜けた後の行には付かない。thunk の結果はそのまま返る。
    @Test
    def testWithFieldsEndsWithThunk(): Unit \ Assert =
        let span = Fields.empty() |> Fields.str("s", "1");
        let (result, records) = Logfx.runWithList(() -> {
            let value = Logfx.withFields(span, () -> { Fields.empty() |> Logfx.info("in"); 42 });
            Fields.empty() |> Logfx.info("out");
            value
        });
        Assert.assertEq(
            expected = (42, List#{(Severity.Info, "in", List#{("s", Logfx.Value.Str("1"))}), (Severity.Info, "out", Nil)}),
            (result, records |> List.map(toTuple)))

    /// runWithList を withFields の内側に置くと fields は付かない（内側の handler が先に行を取るため。順序を間違えた時の症状）。
    @Test
    def testWithFieldsOutsideOfRunDoesNotAttach(): Unit \ Assert =
        let span = Fields.empty() |> Fields.str("s", "1");
        let ((_, innerRecords), outerRecords) = Logfx.runWithList(() -> Logfx.withFields(span, () -> Logfx.runWithList(() -> Fields.empty() |> Logfx.info("x"))));
        Assert.assertEq(
            expected = (List#{(Severity.Info, "x", Nil)}, Nil),
            (innerRecords |> List.map(toTuple), outerRecords |> List.map(toTuple)))

    // ---- Sink の合成 ----

    /// 集めた行を古い順にする。
    def collected(sink: Ref[List[Logfx.Record], Static]): List[(Severity, String, List[(String, Logfx.Value)])] \ IO =
        Ref.get(sink) |> List.reverse |> List.map(toTuple)

    /// 全 severity を 1 行ずつ出す。
    def emitAll(): Unit \ Logfx =
        Fields.empty() |> Logfx.trace("t");
        Fields.empty() |> Logfx.debug("d");
        Fields.empty() |> Logfx.info("i");
        Fields.empty() |> Logfx.warn("w");
        Fields.empty() |> Logfx.error("e");
        Fields.empty() |> Logfx.fatal("f")

    /// minSeverity は境界を含む（Warn なら Warn / Error / Fatal が残る）。
    @Test
    def testSinkMinSeverity(): Unit \ IO + Assert =
        let sink = Ref.fresh(Static, Nil);
        Logfx.runWith(Logfx.Sink.minSeverity(Severity.Warn, Logfx.Sink.collect(sink)), () -> emitAll());
        Assert.assertEq(expected = List#{(Severity.Warn, "w", Nil), (Severity.Error, "e", Nil), (Severity.Fatal, "f", Nil)}, collected(sink))

    /// enrich の fields と span の fields は同じ 1 行に付く。行の fields が一番強く、次に span、enrich は一番弱い。
    @Test
    def testSinkEnrichAndSpanOnOneLine(): Unit \ IO + Assert =
        let sink = Ref.fresh(Static, Nil);
        let service = Fields.empty() |> Fields.str("service", "cms") |> Fields.str("k", "enrich");
        let span = Fields.empty() |> Fields.str("request.id", "r1") |> Fields.str("k", "span");
        run {
            Fields.empty() |> Logfx.info("plain");
            Fields.empty() |> Fields.str("k", "line") |> Logfx.info("line")
        } with Logfx.withFields(span)
          with Logfx.runWith(Logfx.Sink.enrich(service, Logfx.Sink.collect(sink)));
        Assert.assertEq(
            expected = List#{
                (Severity.Info, "plain", List#{("k", Logfx.Value.Str("span")), ("request.id", Logfx.Value.Str("r1")), ("service", Logfx.Value.Str("cms"))}),
                (Severity.Info, "line",  List#{("k", Logfx.Value.Str("line")), ("request.id", Logfx.Value.Str("r1")), ("service", Logfx.Value.Str("cms"))})},
            collected(sink))

    /// json は clock の時刻で toJsonLine の 1 行を out に渡す。
    @Test
    def testSinkJson(): Unit \ IO + Assert =
        let lines = Ref.fresh(Static, Nil);
        Logfx.runWith(Logfx.Sink.json(() -> 1757300000123i64, line -> Ref.put(line :: Ref.get(lines), lines)), () -> Fields.empty() |> Fields.str("k", "v") |> Logfx.info("m"));
        Assert.assertEq(
            expected = List#{"{\"time\":\"2025-09-08T02:53:20.123Z\",\"severity\":\"info\",\"message\":\"m\",\"k\":\"v\"}"},
            Ref.get(lines))

    /// 「boom」の行で例外を投げる sink。
    def throwingSink(record: Logfx.Record): Unit \ IO =
        if (record#message == "boom") throw new RuntimeException("sink failed") else ()

    /// sink が投げても runWith が捨てるので、thunk は最後まで走って結果が返る。
    @Test
    def testRunWithSwallowsSinkFailure(): Unit \ IO + Assert =
        let result = Logfx.runWith(throwingSink, () -> {
            Fields.empty() |> Logfx.info("boom");
            Fields.empty() |> Logfx.info("after");
            42
        });
        Assert.assertEq(expected = 42, result)

    /// tee は両方に同じ行を渡す。first が投げても second には届く。
    @Test
    def testSinkTeeReachesBothEvenIfFirstThrows(): Unit \ IO + Assert =
        let sink = Ref.fresh(Static, Nil);
        let other = Ref.fresh(Static, Nil);
        Logfx.runWith(Logfx.Sink.tee(Logfx.Sink.collect(other), Logfx.Sink.collect(sink)), () -> Fields.empty() |> Logfx.info("both"));
        Logfx.runWith(Logfx.Sink.tee(throwingSink, Logfx.Sink.collect(sink)), () -> Fields.empty() |> Logfx.info("boom"));
        Assert.assertEq(
            expected = (List#{(Severity.Info, "both", Nil)},
                        List#{(Severity.Info, "both", Nil), (Severity.Info, "boom", Nil)}),
            (collected(other), collected(sink)))

    /// fallback は primary が投げた行だけを secondary に回し、logfx.fallback_reason を付ける。投げなければ secondary は空。
    @Test
    def testSinkFallback(): Unit \ IO + Assert =
        let sink = Ref.fresh(Static, Nil);
        Logfx.runWith(Logfx.Sink.fallback(throwingSink, Logfx.Sink.collect(sink)), () -> {
            Fields.empty() |> Logfx.info("ok");
            Fields.empty() |> Fields.str("k", "v") |> Logfx.info("boom")
        });
        Assert.assertEq(
            expected = List#{(Severity.Info, "boom", List#{("k", Logfx.Value.Str("v")), ("logfx.fallback_reason", Logfx.Value.Str("java.lang.RuntimeException: sink failed"))})},
            collected(sink))

    // ---- enabled（段の判定）----

    /// runWithMin は min より軽い段で enabled が false になる（min は残す）。
    @Test
    def testRunWithMinAnswersEnabled(): Unit \ IO + Assert =
        let answers = Logfx.runWith(Logfx.Sink.silent(), () ->
            (Logfx.enabled(Severity.Trace), Logfx.enabled(Severity.Fatal)));
        let limited = Logfx.runWithMin(Severity.Warn, Logfx.Sink.silent(), () ->
            (Logfx.enabled(Severity.Debug), Logfx.enabled(Severity.Warn), Logfx.enabled(Severity.Error)));
        Assert.assertEq(expected = ((true, true), (false, true, true)), (answers, limited))

    /// runWithMin で落ちる段は sink に届かない。
    @Test
    def testRunWithMinDropsLightLines(): Unit \ IO + Assert =
        let sink = Ref.fresh(Static, Nil);
        Logfx.runWithMin(Severity.Warn, Logfx.Sink.collect(sink), () -> emitAll());
        Assert.assertEq(expected = List#{(Severity.Warn, "w", Nil), (Severity.Error, "e", Nil), (Severity.Fatal, "f", Nil)}, collected(sink))

    /// infoWith は落ちる段では fields を組み立てない。残る段では組み立てて emit する。
    @Test
    def testLogWithSkipsBuildingFields(): Unit \ IO + Assert =
        let built = Ref.fresh(Static, 0);
        let sink = Ref.fresh(Static, Nil);
        Logfx.runWithMin(Severity.Warn, Logfx.Sink.collect(sink), () -> {
            Logfx.infoWith("dropped", () -> { Ref.put(Ref.get(built) + 1, built); Fields.empty() |> Fields.str("k", "v") });
            Logfx.warnWith("kept", () -> { Ref.put(Ref.get(built) + 1, built); Fields.empty() |> Fields.str("k", "v") })
        });
        Assert.assertEq(
            expected = (1, List#{(Severity.Warn, "kept", List#{("k", Logfx.Value.Str("v"))})}),
            (Ref.get(built), collected(sink)))

    /// withFields の中でも段の判定は外の handler に届く。残る行には span の fields が付く。
    @Test
    def testWithFieldsForwardsEnabled(): Unit \ IO + Assert =
        let sink = Ref.fresh(Static, Nil);
        let span = Fields.empty() |> Fields.str("request.id", "r1");
        Logfx.runWithMin(Severity.Warn, Logfx.Sink.collect(sink), () -> Logfx.withFields(span, () -> {
            let seen = Logfx.enabled(Severity.Debug);
            Fields.empty() |> Fields.bool("debug.enabled", seen) |> Logfx.warn("kept");
            Fields.empty() |> Logfx.info("dropped")
        }));
        Assert.assertEq(
            expected = List#{(Severity.Warn, "kept", List#{("debug.enabled", Logfx.Value.Bool(false)), ("request.id", Logfx.Value.Str("r1"))})},
            collected(sink))

    /// runWithList は全段を集める（テストで落ちる段を気にしなくてよい）。
    @Test
    def testRunWithListEnablesEverySeverity(): Unit \ Assert =
        let (answer, records) = Logfx.runWithList(() -> {
            let seen = Logfx.enabled(Severity.Trace);
            Logfx.traceWith("t", () -> Fields.empty());
            seen
        });
        Assert.assertEq(expected = (true, List#{(Severity.Trace, "t", Nil)}), (answer, records |> List.map(toTuple)))

    // ---- exception ----

    /// exception の 3 フィールドの値を (type, message, stacktrace の行) にする。
    def exceptionTriple(error: Throwable): (Option[Logfx.Value], Option[Logfx.Value], List[String]) \ IO =
        let fields = Fields.empty() |> Logfx.exception(error);
        (Map.get("exception.type", fields), Map.get("exception.message", fields),
         Map.get("exception.stacktrace", fields) |> Option.flatMap(Logfx.valueAsStr) |> Option.map(String.splitOn(substr = " | ")) |> Option.getWithDefault(Nil))

    /// n 段の再帰の底で投げる。Flix の frame が 8 つより多く積まれる。
    def deep(n: Int32): Int32 \ IO =
        if (n == 0) throw new IllegalStateException("deep") else 1 + deep(n - 1)

    /// deep(20) の例外を捕まえる。
    def thrownDeep(): Throwable \ IO =
        try {
            checked_cast(new RuntimeException("not thrown ${deep(20)}"))
        } catch {
            case e: IllegalStateException => checked_cast(e)
        }

    /// 3 フィールドが付く。type はクラス名、message はそのまま、stacktrace は Flix の frame（Def$ / Clo$）だけを 8 つ。
    @Test
    def testExceptionFields(): Unit \ IO + Assert =
        let (kind, message, lines) = exceptionTriple(thrownDeep());
        Assert.assertEq(
            expected = (Some(Logfx.Value.Str("java.lang.IllegalStateException")), Some(Logfx.Value.Str("deep")), 8, true),
            (kind, message, List.length(lines), lines |> List.forAll(line -> String.contains(substr = "Def$", line) or String.contains(substr = "Clo$", line))))

    /// message が null なら空。Detail: 以降（PG の詳細。値が入りうる）は落ち、200 字で切る。
    @Test
    def testExceptionMessageTable(): Unit \ IO + Assert =
        let cases: List[(Throwable, String)] = List#{
            (checked_cast(new VerifyError()),                                              ""),
            (checked_cast(new RuntimeException("syntax error\n  Detail: Key (x)=(1) exists.")), "syntax error"),
            (checked_cast(new RuntimeException(String.repeat(300, "x"))),                  String.repeat(200, "x"))
        };
        Assert.assertEq(
            expected = cases |> List.map(match (_, expected) -> Some(Logfx.Value.Str(expected))),
            cases |> List.map(match (error, _) -> Fields.empty() |> Logfx.exception(error) |> Map.get("exception.message")))

    /// cause を "型: message" で 3 段まで辿る。4 段目より奥（本当の一番底）は出ない。
    @Test
    def testExceptionCauseChain(): Unit \ IO + Assert =
        let deepest: Throwable = checked_cast(new ArithmeticException("deepest"));
        let third: Throwable = checked_cast(new IllegalStateException("c3", deepest));
        let second: Throwable = checked_cast(new RuntimeException("c2", third));
        let first: Throwable = checked_cast(new IllegalStateException("c1", second));
        let outer: Throwable = checked_cast(new RuntimeException("outer", first));
        Assert.assertEq(
            expected = Some(Logfx.Value.Str("java.lang.IllegalStateException: c1 <- java.lang.RuntimeException: c2 <- java.lang.IllegalStateException: c3")),
            Fields.empty() |> Logfx.exception(outer) |> Map.get("exception.cause"))

    /// 1 段だけ包んだ例外（JDBC が SQLException を包む形）でも、本当の理由が出る。
    @Test
    def testExceptionCauseOfWrapped(): Unit \ IO + Assert =
        let cause: Throwable = checked_cast(new ArithmeticException("/ by zero"));
        Assert.assertEq(
            expected = Some(Logfx.Value.Str("java.lang.ArithmeticException: / by zero")),
            Fields.empty() |> Logfx.exception(checked_cast(new RuntimeException("query failed", cause))) |> Map.get("exception.cause"))

    /// cause が無ければ exception.cause は付かない（毎行に空の欄を増やさない）。
    @Test
    def testExceptionWithoutCauseHasNoCauseField(): Unit \ IO + Assert =
        Assert.assertEq(
            expected = None,
            Fields.empty() |> Logfx.exception(checked_cast(new RuntimeException("x"))) |> Map.get("exception.cause"))

    /// stacktrace の区切りは制御文字でない（toJsonLine が制御文字を落とすので、改行だと frame が全部繋がる）。
    @Test
    def testExceptionStacktraceSurvivesJsonLine(): Unit \ IO + Assert =
        let fields = Fields.empty() |> Logfx.exception(thrownDeep());
        let line = Logfx.toJsonLine(0i64, recordOf(Severity.Error, "m", fields));
        Assert.assertEq(expected = (8, true), (List.length(String.splitOn(substr = " | ", line)), String.contains(substr = "Def$", line)))

    /// 既にある fields はそのまま残り、stacktrace のフィールドは必ず付く。
    @Test
    def testExceptionKeepsExistingFields(): Unit \ IO + Assert =
        let fields = Fields.empty() |> Fields.str("k", "v") |> Logfx.exception(checked_cast(new RuntimeException("x")));
        Assert.assertEq(
            expected = (Some(Logfx.Value.Str("v")), true),
            (Map.get("k", fields), Map.memberOf("exception.stacktrace", fields)))

}

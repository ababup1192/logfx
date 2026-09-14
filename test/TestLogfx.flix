///
/// Log: the shape of a one-line JSON record (toJsonLine), the Fields builder, spans (withFields), Sink composition, and the copy of a Java exception (exception).
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
    /// Turn a Record into (severity, message, list of fields) so it is easy to compare.
    ///
    def toTuple(record: Logfx.Record): (Severity, String, List[(String, Logfx.Value)]) =
        (record#severity, record#message, Map.toList(record#fields))

    ///
    /// Build a Record from severity, message and fields.
    ///
    def recordOf(severity: Severity, message: String, fields: Fields): Logfx.Record =
        { severity = severity, message = message, fields = fields }

    // ---- toJsonLine ----

    /// Key order puts time / severity / message first and sorts the rest by name; severity is lowercase; numbers, booleans and lists keep their own type.
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

    /// Control characters (newlines, escape sequences) are dropped from the message, from string fields and from inside lists (prevents log injection).
    @Test
    def testToJsonLineDropsControlChars(): Unit \ Assert =
        Assert.assertEq(
            expected = "{\"time\":\"1970-01-01T00:00:00.000Z\",\"severity\":\"info\",\"message\":\"ab[31m\",\"l\":[\"x\"],\"p\":\"/health{\\\"fake\\\":1}\"}",
            Logfx.toJsonLine(0i64, recordOf(Severity.Info, "a\nb[31m", Fields.empty() |> Fields.str("p", "/health\n{\"fake\":1}\r") |> Fields.strs("l", List#{"x\t"}))))

    /// Setting the same key twice keeps the later value.
    @Test
    def testToJsonLineLastKeyWins(): Unit \ Assert =
        Assert.assertEq(
            expected = "{\"time\":\"1970-01-01T00:00:00.000Z\",\"severity\":\"info\",\"message\":\"m\",\"k\":\"2\"}",
            Logfx.toJsonLine(0i64, recordOf(Severity.Info, "m", Fields.empty() |> Fields.str("k", "1") |> Fields.str("k", "2"))))

    /// Even if fields contain time / severity / message, the leading three win and are not emitted twice.
    @Test
    def testToJsonLineHeaderKeysWin(): Unit \ Assert =
        Assert.assertEq(
            expected = "{\"time\":\"1970-01-01T00:00:00.000Z\",\"severity\":\"info\",\"message\":\"m\"}",
            Logfx.toJsonLine(0i64, recordOf(Severity.Info, "m", Fields.empty() |> Fields.str("time", "x") |> Fields.str("severity", "y") |> Fields.str("message", "z"))))

    /// time is ISO 8601 UTC with fixed ms: .000Z even for 0, and leap days, year 9999 and negative times (before 1970) all render.
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

    /// Float NaN and Infinity cannot be written in JSON, so they become null.
    @Test
    def testToJsonLineNonFiniteIsNull(): Unit \ Assert =
        Assert.assertEq(
            expected = "{\"time\":\"1970-01-01T00:00:00.000Z\",\"severity\":\"info\",\"message\":\"m\",\"inf\":null,\"nan\":null}",
            Logfx.toJsonLine(0i64, recordOf(Severity.Info, "m", Map#{"nan" => Logfx.Value.Float(Float64.nan()), "inf" => Logfx.Value.Float(Float64.positiveInfinity())})))

    // ---- Fields ----

    /// str / int / bool / strs produce the Logfx.Value of that type; opt with None adds nothing, and Some is the same as str.
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

    /// merge lets other win (same key takes other's value, keys present on only one side are both kept).
    @Test
    def testFieldsMergeOtherWins(): Unit \ Assert =
        Assert.assertEq(
            expected = List#{("a", Logfx.Value.Str("other")), ("b", Logfx.Value.Str("base")), ("c", Logfx.Value.Str("other"))},
            Fields.empty() |> Fields.str("a", "base") |> Fields.str("b", "base")
                |> Fields.merge(Fields.empty() |> Fields.str("a", "other") |> Fields.str("c", "other"))
                |> Map.toList)

    /// int holds values that do not fit in Int32 without rounding, and JSON keeps those digits (byte counts over 2 GB, microsecond totals).
    @Test
    def testFieldsIntKeepsInt64(): Unit \ Assert =
        let fields = Fields.empty() |> Fields.int("hi", Int64.maxValue()) |> Fields.int("lo", Int64.minValue());
        Assert.assertEq(
            expected = (List#{("hi", Logfx.Value.Int(Int64.maxValue())), ("lo", Logfx.Value.Int(Int64.minValue()))},
                        "{\"time\":\"1970-01-01T00:00:00.000Z\",\"severity\":\"info\",\"message\":\"m\",\"n\":3000000000}"),
            (Map.toList(fields), Logfx.toJsonLine(0i64, recordOf(Severity.Info, "m", Fields.empty() |> Fields.int("n", 3000000000i64)))))

    /// float / obj / value produce the Logfx.Value of that shape (value can also hold Null).
    @Test
    def testFieldsCoversEveryValue(): Unit \ Assert =
        let cases = List#{
            (Fields.empty() |> Fields.float("k", 1.5),                                List#{("k", Logfx.Value.Float(1.5))}),
            (Fields.empty() |> Fields.obj("k", Fields.empty() |> Fields.str("a", "b")), List#{("k", Logfx.Value.Obj(Map#{"a" => Logfx.Value.Str("b")}))}),
            (Fields.empty() |> Fields.value("k", Logfx.Value.Null),                   List#{("k", Logfx.Value.Null)})
        };
        Assert.assertEq(expected = cases |> List.map(snd), cases |> List.map(match (fields, _) -> Map.toList(fields)))

    /// valueAs* extracts only its own case and gives None for other cases; valueIsNull is true only for Null.
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

    // ---- withFields (span) ----

    /// The outer fields are attached to every line inside; severity is that of the function called.
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

    /// For the same key the inner one (closer to the line) wins; nested spans also let the inner one win.
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

    /// Lines after the thunk returns get nothing attached; the thunk's result is returned as is.
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

    /// Putting runWithList inside withFields attaches no fields (the inner handler takes the line first; this is the symptom of getting the order wrong).
    @Test
    def testWithFieldsOutsideOfRunDoesNotAttach(): Unit \ Assert =
        let span = Fields.empty() |> Fields.str("s", "1");
        let ((_, innerRecords), outerRecords) = Logfx.runWithList(() -> Logfx.withFields(span, () -> Logfx.runWithList(() -> Fields.empty() |> Logfx.info("x"))));
        Assert.assertEq(
            expected = (List#{(Severity.Info, "x", Nil)}, Nil),
            (innerRecords |> List.map(toTuple), outerRecords |> List.map(toTuple)))

    // ---- Sink composition ----

    /// Put the collected lines in oldest-first order.
    def collected(sink: Ref[List[Logfx.Record], Static]): List[(Severity, String, List[(String, Logfx.Value)])] \ IO =
        Ref.get(sink) |> List.reverse |> List.map(toTuple)

    /// Emit one line for every severity.
    def emitAll(): Unit \ Logfx =
        Fields.empty() |> Logfx.trace("t");
        Fields.empty() |> Logfx.debug("d");
        Fields.empty() |> Logfx.info("i");
        Fields.empty() |> Logfx.warn("w");
        Fields.empty() |> Logfx.error("e");
        Fields.empty() |> Logfx.fatal("f")

    /// minSeverity includes the boundary (Warn keeps Warn / Error / Fatal).
    @Test
    def testSinkMinSeverity(): Unit \ IO + Assert =
        let sink = Ref.fresh(Static, Nil);
        Logfx.runWith(Logfx.Sink.minSeverity(Severity.Warn, Logfx.Sink.collect(sink)), () -> emitAll());
        Assert.assertEq(expected = List#{(Severity.Warn, "w", Nil), (Severity.Error, "e", Nil), (Severity.Fatal, "f", Nil)}, collected(sink))

    /// The enrich fields and the span fields land on the same line; the line's own fields are strongest, then the span, and enrich is weakest.
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

    /// json passes one toJsonLine line, timestamped by clock, to out.
    @Test
    def testSinkJson(): Unit \ IO + Assert =
        let lines = Ref.fresh(Static, Nil);
        Logfx.runWith(Logfx.Sink.json(() -> checked_ecast(1757300000123i64), line -> Ref.put(line :: Ref.get(lines), lines)), () -> Fields.empty() |> Fields.str("k", "v") |> Logfx.info("m"));
        Assert.assertEq(
            expected = List#{"{\"time\":\"2025-09-08T02:53:20.123Z\",\"severity\":\"info\",\"message\":\"m\",\"k\":\"v\"}"},
            Ref.get(lines))

    /// A sink that throws on the "boom" line.
    def throwingSink(record: Logfx.Record): Unit \ IO =
        if (record#message == "boom") throw new RuntimeException("sink failed") else ()

    /// runWith discards a throwing sink, so the thunk runs to the end and returns its result.
    @Test
    def testRunWithSwallowsSinkFailure(): Unit \ IO + Assert =
        let result = Logfx.runWith(throwingSink, () -> {
            Fields.empty() |> Logfx.info("boom");
            Fields.empty() |> Logfx.info("after");
            42
        });
        Assert.assertEq(expected = 42, result)

    /// tee passes the same line to both; even if first throws, second still receives it.
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

    /// fallback sends only the lines primary threw on to secondary and adds logfx.fallback_reason; if nothing throws, secondary stays empty.
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

    // ---- enabled (severity check) ----

    /// runWithMin makes enabled false for severities lighter than min (min itself is kept).
    @Test
    def testRunWithMinAnswersEnabled(): Unit \ IO + Assert =
        let answers = Logfx.runWith(Logfx.Sink.silent(), () ->
            (Logfx.enabled(Severity.Trace), Logfx.enabled(Severity.Fatal)));
        let limited = Logfx.runWithMin(Severity.Warn, Logfx.Sink.silent(), () ->
            (Logfx.enabled(Severity.Debug), Logfx.enabled(Severity.Warn), Logfx.enabled(Severity.Error)));
        Assert.assertEq(expected = ((true, true), (false, true, true)), (answers, limited))

    /// Severities dropped by runWithMin never reach the sink.
    @Test
    def testRunWithMinDropsLightLines(): Unit \ IO + Assert =
        let sink = Ref.fresh(Static, Nil);
        Logfx.runWithMin(Severity.Warn, Logfx.Sink.collect(sink), () -> emitAll());
        Assert.assertEq(expected = List#{(Severity.Warn, "w", Nil), (Severity.Error, "e", Nil), (Severity.Fatal, "f", Nil)}, collected(sink))

    /// infoWith does not build the fields for a dropped severity; for a kept severity it builds them and emits.
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

    /// Inside withFields the severity check still reaches the outer handler; kept lines get the span fields.
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

    /// runWithList collects every severity (tests need not care about dropped severities).
    @Test
    def testRunWithListEnablesEverySeverity(): Unit \ Assert =
        let (answer, records) = Logfx.runWithList(() -> {
            let seen = Logfx.enabled(Severity.Trace);
            Logfx.traceWith("t", () -> Fields.empty());
            seen
        });
        Assert.assertEq(expected = (true, List#{(Severity.Trace, "t", Nil)}), (answer, records |> List.map(toTuple)))

    // ---- exception ----

    /// Turn the three exception fields into (type, message, stacktrace lines).
    def exceptionTriple(error: Throwable): (Option[Logfx.Value], Option[Logfx.Value], List[String]) \ IO =
        let fields = Fields.empty() |> Logfx.exception(error);
        (Map.get("exception.type", fields), Map.get("exception.message", fields),
         Map.get("exception.stacktrace", fields) |> Option.flatMap(Logfx.valueAsStr) |> Option.map(String.splitOn(substr = " | ")) |> Option.getWithDefault(Nil))

    /// Throw at the bottom of n levels of recursion, so more than 8 Flix frames are stacked.
    def deep(n: Int32): Int32 \ IO =
        if (n == 0) throw new IllegalStateException("deep") else 1 + deep(n - 1)

    /// Catch the exception from deep(20).
    def thrownDeep(): Throwable \ IO =
        try {
            checked_cast(new RuntimeException("not thrown ${deep(20)}"))
        } catch {
            case e: IllegalStateException => checked_cast(e)
        }

    /// Three fields are attached: type is the class name, message is unchanged, and stacktrace holds 8 Flix frames (Def$ / Clo$) only.
    @Test
    def testExceptionFields(): Unit \ IO + Assert =
        let (kind, message, lines) = exceptionTriple(thrownDeep());
        Assert.assertEq(
            expected = (Some(Logfx.Value.Str("java.lang.IllegalStateException")), Some(Logfx.Value.Str("deep")), 8, true),
            (kind, message, List.length(lines), lines |> List.forAll(line -> String.contains(substr = "Def$", line) or String.contains(substr = "Clo$", line))))

    /// A null message becomes empty; everything from "Detail:" on (the PG detail, which can contain values) is dropped, and the text is cut at 200 characters.
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

    /// Causes are followed as "type: message" for up to 3 levels; anything deeper than the 4th level (the real bottom) is not emitted.
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

    /// Even for an exception wrapped just once (the shape JDBC uses to wrap a SQLException), the real reason is emitted.
    @Test
    def testExceptionCauseOfWrapped(): Unit \ IO + Assert =
        let cause: Throwable = checked_cast(new ArithmeticException("/ by zero"));
        Assert.assertEq(
            expected = Some(Logfx.Value.Str("java.lang.ArithmeticException: / by zero")),
            Fields.empty() |> Logfx.exception(checked_cast(new RuntimeException("query failed", cause))) |> Map.get("exception.cause"))

    /// With no cause, exception.cause is not attached (no empty column added to every line).
    @Test
    def testExceptionWithoutCauseHasNoCauseField(): Unit \ IO + Assert =
        Assert.assertEq(
            expected = None,
            Fields.empty() |> Logfx.exception(checked_cast(new RuntimeException("x"))) |> Map.get("exception.cause"))

    /// A frame is shaped Class.method(FileName:line); no path is included, and frames without a line number are not emitted.
    @Test
    def testExceptionFrameShape(): Unit \ IO + Assert =
        let (_, _, lines) = exceptionTriple(thrownDeep());
        Assert.assertEq(
            expected = (true, false, false),
            (lines |> List.forAll(line -> String.isMatch(regex = ".+\\(TestLogfx\\.flix:[0-9]+\\)", line)),
             lines |> List.exists(line -> String.contains(substr = "/", line)),
             lines |> List.exists(line -> String.contains(substr = ":-1)", line) or String.contains(substr = ":0)", line))))

    /// The stacktrace separator is not a control character (toJsonLine drops control characters, so a newline would join all frames together).
    @Test
    def testExceptionStacktraceSurvivesJsonLine(): Unit \ IO + Assert =
        let fields = Fields.empty() |> Logfx.exception(thrownDeep());
        let line = Logfx.toJsonLine(0i64, recordOf(Severity.Error, "m", fields));
        Assert.assertEq(expected = (8, true), (List.length(String.splitOn(substr = " | ", line)), String.contains(substr = "Def$", line)))

    /// Existing fields are kept as they are, and the stacktrace field is always attached.
    @Test
    def testExceptionKeepsExistingFields(): Unit \ IO + Assert =
        let fields = Fields.empty() |> Fields.str("k", "v") |> Logfx.exception(checked_cast(new RuntimeException("x")));
        Assert.assertEq(
            expected = (Some(Logfx.Value.Str("v")), true),
            (Map.get("k", fields), Map.memberOf("exception.stacktrace", fields)))

}

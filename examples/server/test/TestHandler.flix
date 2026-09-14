///
/// Handler のログ。span が全行に付く事、経路ごとに出る段と message、例外の写しが付く事。
///
/// WhyNot: 1 行 JSON の文字列で比べない。キーの順と時刻の形は logfx の仕事なので、文字列で
/// 比べると、意味の変わっていない版上げでこのテストが落ちる。見るのは段・message・キー。
///
/// WhyNot: runWithList の代わりに Sink.collect を使わない。collect は Ref と IO が要るのに対し、
/// runWithList は純粋で全段が有効なので、LOG_LEVEL の設定にテストが引きずられない。
///
mod TestHandler {

    use Logfx.Severity

    /// 行を (段, message, キーの一覧) にする。
    def shapes(records: List[Logfx.Record]): List[(Severity, String, List[String])] =
        records |> List.map(record -> (record#severity, record#message, Map.keysOf(record#fields) |> Set.toList))

    /// message で 1 行を取る。無ければテストの誤り。
    def lineOf(message: String, records: List[Logfx.Record]): Logfx.Record =
        match List.find(record -> record#message == message, records) {
            case Some(record) => record
            case None         => bug!("'${message}' の行が無い（テストの誤り）")
        }

    /// 行に付いた 1 つのフィールド。
    def field(key: String, record: Logfx.Record): Option[Logfx.Value] =
        Map.get(key, record#fields)

    // ---- span ----

    /// span は thunk の中で出た全行に付く。routing は debug、無い経路は warn で、status は 404。
    @Test
    def testHandlerSpanIsOnEveryLine(): Unit \ {Assert, IO} =
        let (status, records) = Logfx.runWithList(() -> Handler.handle("r1", "GET", "/nope"));
        Assert.assertEq(
            expected = (404, List#{
                (Severity.Debug, "routing",  List#{"http.request.method", "request.id", "route.pattern", "url.path"}),
                (Severity.Warn,  "no route", List#{"http.request.method", "request.id", "url.path"})}),
            (status, shapes(records)))

    /// 経路ごとに出る段と message。
    @Test
    def testHandlerRouteTable(): Unit \ {Assert, IO} =
        let table = List#{
            ("/health", (200, List#{(Severity.Debug, "routing")})),
            ("/nope",   (404, List#{(Severity.Debug, "routing"), (Severity.Warn, "no route")})),
            ("/posts",  (500, List#{(Severity.Debug, "routing"), (Severity.Error, "request failed")}))
        };
        Assert.assertEq(
            expected = table |> List.map(snd),
            table |> List.map(match (path, _) -> {
                let (status, records) = Logfx.runWithList(() -> Handler.handle("r1", "GET", path));
                (status, records |> List.map(record -> (record#severity, record#message)))
            }))

    // ---- 例外 ----

    /// Logfx.exception は型・message・cause・stacktrace を 1 行に足す（cause が無ければ付かない）。
    @Test
    def testHandlerExceptionIsAttached(): Unit \ {Assert, IO} =
        let (_, records) = Logfx.runWithList(() -> Handler.handle("r2", "GET", "/posts"));
        let failed = lineOf("request failed", records);
        Assert.assertEq(
            expected = (Some(Logfx.Value.Str("java.lang.RuntimeException")),
                        Some(Logfx.Value.Str("connection refused")),
                        Some(Logfx.Value.Int(500i64)),
                        None),
            (field("exception.type", failed),
             field("exception.message", failed),
             field("http.response.status_code", failed),
             field("exception.cause", failed)))

}

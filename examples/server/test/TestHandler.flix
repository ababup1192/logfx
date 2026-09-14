///
/// What Handler logs: the span on every line, the severity and message per route, and the
/// exception fields on a failure.
///
/// WhyNot: not compared as a line of JSON. The key order and the timestamp format are logfx's
/// business, so comparing the string makes this test fail on an upgrade that changed nothing it
/// meant to check. What it looks at is the severity, the message and the keys.
///
/// WhyNot: Sink.collect is not used in place of runWithList. collect needs a Ref and IO, while
/// runWithList is pure and enables every severity, so the test does not follow LOG_LEVEL.
///
mod TestHandler {

    use Logfx.Severity

    /// A line as (severity, message, the keys on it).
    def shapes(records: List[Logfx.Record]): List[(Severity, String, List[String])] =
        records |> List.map(record -> (record#severity, record#message, Map.keysOf(record#fields) |> Set.toList))

    /// One line by its message. Its absence is an error in the test.
    def lineOf(message: String, records: List[Logfx.Record]): Logfx.Record =
        match List.find(record -> record#message == message, records) {
            case Some(record) => record
            case None         => bug!("no line with the message '${message}' (the test is wrong)")
        }

    /// One field on a line.
    def field(key: String, record: Logfx.Record): Option[Logfx.Value] =
        Map.get(key, record#fields)

    // ---- Spans ----

    /// The span is on every line emitted inside the thunk. routing is debug, an unknown route is warn, and the status is 404.
    @Test
    def testHandlerSpanIsOnEveryLine(): Unit \ {Assert, IO} =
        let (status, records) = Logfx.runWithList(() -> Handler.handle("r1", "GET", "/nope"));
        Assert.assertEq(
            expected = (404, List#{
                (Severity.Debug, "routing",  List#{"http.request.method", "request.id", "route.pattern", "url.path"}),
                (Severity.Warn,  "no route", List#{"http.request.method", "request.id", "url.path"})}),
            (status, shapes(records)))

    /// The severity and message emitted per route.
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

    // ---- Exceptions ----

    /// Logfx.exception adds the type, message, cause and stacktrace to one line (no cause field when there is no cause).
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

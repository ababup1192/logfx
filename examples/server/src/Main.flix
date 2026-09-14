import java.lang.System

///
/// The entry point. Everything logfx needs decided is gathered here: where lines are written,
/// where they go when that breaks, what every line carries, and from which severity up.
///
def main(): Unit \ IO =
    let sink = Server.sink();
    let min = Server.minSeverity();
    region rc {
        List.forEach(request -> {
            let (requestId, method, path) = request;
            spawn {
                run {
                    Handler.handle(requestId, method, path)
                } with Logfx.runWithMin(min, sink)
            } @ rc
        }, Server.incoming())
    }

///
/// The wiring: build the sink, pick the severity, install the handler once per request.
///
/// WhyNot: main is not wrapped in a single runWithMin with the spawns inside it. Logfx is an
/// effect, so a handler does not cross a thread: calling Logfx.info inside such a spawn fails with
/// "Unable to unify the effect formulas: 'Logfx' and '(Chan + IO + NonDet) & e0'".
/// What crosses is the sink, which is a value and can simply be passed.
///
mod Server {

    use Logfx.Fields
    use Logfx.Severity

    import java.lang.System

    // ---- Wiring ----

    ///
    /// One sink, shared by every request. `enrich` puts service.* on every line, and `fallback`
    /// names where a line goes on the day stdout breaks (with logfx.fallback_reason attached).
    ///
    /// WhyNot: not built per request. A sink is a value and carries no state to keep apart.
    ///
    pub def sink(): Logfx.Sink =
        let service = Fields.empty()
            |> Fields.str("service.name", "example-server")
            |> Fields.str("service.version", "0.0.0");
        let toStdout = Logfx.Sink.json(_ -> System.currentTimeMillis(), line -> println(line));
        let toStderr = Logfx.Sink.json(_ -> System.currentTimeMillis(), line -> System.err.println(line));
        Logfx.Sink.enrich(service, Logfx.Sink.fallback(toStdout, toStderr))

    ///
    /// The severity from LOG_LEVEL. Unset, or a word that is not a severity, means Info.
    ///
    /// WhyNot: an unknown word is not fatal. A server that refuses to start over a typo in the
    /// configuration costs more than logging one severity off.
    ///
    /// WhyNot: the severity test is not left to Sink.minSeverity. Dropping the line at the sink
    /// means the fields were built anyway; runWithMin lets debugWith skip the building too.
    ///
    pub def minSeverity(): Severity \ IO =
        let text: String = System.getenv("LOG_LEVEL");
        if (Object.isNull(text)) Severity.Info
        else Logfx.parseSeverity(text) |> Option.getWithDefault(Severity.Info)

    /// Stands in for the listener. Hands over (request.id, method, path) in turn.
    pub def incoming(): List[(String, String, String)] =
        List#{("r1", "GET", "/health"), ("r2", "GET", "/posts"), ("r3", "GET", "/nope")}

}

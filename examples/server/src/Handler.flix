///
/// One request. This is where the caller's code normally lives: no sink and no handler in sight.
///
/// WhyNot: runWith is not called here. It would burn the destination into this function and a test
/// could no longer swap it. The handler goes once, at the entry of a thread (Server).
///
/// WhyNot: a logger is not taken as a parameter. Logfx is an effect, so it travels by handler and
/// not by the call chain. Passing it along would make every function on the route know about it.
///
mod Handler {

    use Logfx.Fields

    import java.lang.RuntimeException
    import java.lang.Throwable

    // ---- Entry ----

    ///
    /// Handles one request and answers with an HTTP status code.
    ///
    /// The effect is `{IO, Logfx}`: `Logfx` because it logs, `IO` because the work itself does.
    /// Where the lines go is decided by whoever handles `Logfx` (Server).
    ///
    pub def handle(requestId: String, method: String, path: String): Int32 \ {IO, Logfx} =
        run {
            route(path)
        } with Logfx.withFields(span(requestId, method, path))

    ///
    /// The span for a request. Every line emitted inside it carries these.
    ///
    /// WhyNot: the path is not left out for being high cardinality. `url.path` is the OTel name for
    /// the path as it came in, and what you group by is `route.pattern`, which is emitted too.
    ///
    def span(requestId: String, method: String, path: String): Fields =
        Fields.empty()
            |> Fields.str("request.id", requestId)
            |> Fields.str("http.request.method", method)
            |> Fields.str("url.path", path)

    // ---- Routes ----

    /// Dispatch. This runs inside the span, so every line below carries request.id and the rest.
    def route(path: String): Int32 \ {IO, Logfx} =
        // An expensive line is built only when its severity is on: the thunk of debugWith
        // runs only when `enabled` answers true.
        Logfx.debugWith("routing", () -> Fields.empty() |> Fields.str("route.pattern", pattern(path)));
        match path {
            case "/posts"  => listPosts()
            case "/health" => 200
            case _         =>
                Logfx.warn("no route", Fields.empty());
                404
        }

    /// A listing. A count is an Int32, so it goes through Int32.toInt64 (Fields.int takes Int64).
    def listPosts(): Int32 \ {IO, Logfx} =
        try {
            let posts = fetchPosts();
            Fields.empty()
                |> Fields.int("db.response.returned_rows", Int32.toInt64(List.length(posts)))
                |> Fields.int("http.response.status_code", 200i64)
                |> Logfx.info("request finished");
            200
        } catch {
            case error: Throwable =>
                // Logfx.exception adds fields, so it sits in the middle of the pipe.
                Fields.empty()
                    |> Fields.int("http.response.status_code", 500i64)
                    |> Logfx.exception(error)
                    |> Logfx.error("request failed");
                500
        }

    /// The shape of the route, for grouping.
    def pattern(path: String): String =
        if (String.startsWith(prefix = "/posts", path)) "/posts" else path

    ///
    /// Stands in for the database. Throws every time.
    ///
    /// WhyNot: there is no version that succeeds. What this example is here to show is the
    /// exception line, so one route has to fail.
    ///
    def fetchPosts(): List[String] \ IO =
        throw new RuntimeException("connection refused")

}

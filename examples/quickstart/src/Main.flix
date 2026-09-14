//
// The first code block of the README, verbatim.
//
// WhyNot: the README is not the source and this a copy of it — it is the other way round.
// Nobody compiles the code in a README, so the README is always what rots first.
// ci/example.sh builds this on every run, so a rotten example is a red build.
//
import java.lang.System

///
/// Your code takes the effect, not a logger. Who receives the lines is not decided here.
///
def handleRequest(method: String, path: String): Int32 \ Logfx =
    Logfx.Fields.empty()
        |> Logfx.Fields.str("http.request.method", method)
        |> Logfx.Fields.str("url.path", path)
        |> Logfx.Fields.int("http.response.status_code", 200i64)
        |> Logfx.info("request finished");
    200

def main(): Unit \ IO =
    let sink = Logfx.Sink.json(_ -> System.currentTimeMillis(), line -> println(line));
    run {
        discard handleRequest("GET", "/posts")
    } with Logfx.runWithMin(Logfx.Severity.Info, sink)

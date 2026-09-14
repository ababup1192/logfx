//
// logfx as seen from a brand-new project. This only checks that the consumed version actually runs.
// The time is fixed (so the output can be compared line by line).
//
// WhyNot: the logfx tests are not redone here. All that matters here is "can it be consumed as a
// package" (the security setting, whether it compiles without experimental flags, whether the
// published names are visible from outside).
//

import java.lang.ArithmeticException
import java.lang.RuntimeException
import java.lang.Throwable

/// Always the same time (2025-09-08T02:53:20.123Z).
def clock(): Int64 \ IO = checked_ecast(1757300000123i64)

/// A sink that always throws. Used as the primary of fallback.
def brokenSink(_record: Logfx.Record): Unit \ IO = throw new RuntimeException("sink is down")

def main(): Unit \ IO =
    let sink = Logfx.Sink.json(_ -> clock(), line -> println(line));
    Logfx.runWithMin(Logfx.Severity.Info, sink, () -> {
        Logfx.Fields.empty()
            |> Logfx.Fields.str("http.request.method", "GET")
            |> Logfx.Fields.int("http.response.status_code", 200i64)
            |> Logfx.Fields.int("http.response.body.size", 3000000000i64)
            |> Logfx.Fields.float("duration.ratio", 0.5)
            |> Logfx.Fields.bool("cache.hit", true)
            |> Logfx.Fields.strs("graphql.error_codes", List#{"NONE"})
            |> Logfx.Fields.obj("user", Logfx.Fields.empty() |> Logfx.Fields.str("id", "u1"))
            |> Logfx.Fields.value("trace.id", Logfx.Value.Null)
            |> Logfx.info("request finished");
        Logfx.debugWith("dropped", () -> Logfx.Fields.empty() |> Logfx.Fields.str("built", "yes"));
        Logfx.withFields(Logfx.Fields.empty() |> Logfx.Fields.str("request.id", "r1"), () -> {
            let cause: Throwable = checked_cast(new ArithmeticException("/ by zero"));
            Logfx.Fields.empty()
                |> Logfx.exception(checked_cast(new RuntimeException("query failed", cause)))
                |> Logfx.error("insert failed")
        })
    });
    // The line from the broken sink falls through to secondary and gets a reason attached.
    Logfx.runWith(Logfx.Sink.fallback(brokenSink, Logfx.Sink.tee(Logfx.Sink.silent(), sink)), () ->
        Logfx.Fields.empty() |> Logfx.warn("primary is down"))

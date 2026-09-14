//
// What one logfx line costs, in nanoseconds.
//
// Reads as JSON on stdout, one object per case, so ci/bench.sh can compare it to a baseline.
//
// WhyNot: not a @Test. Flix has no benchmark command, and a test that takes seconds and passes
// or fails on a timing would be red on a busy machine for no reason.
//
import java.lang.IllegalStateException
import java.lang.RuntimeException
import java.lang.System
import java.lang.Throwable

///
/// Iterations per round, rounds per case, and rounds thrown away first.
///
/// WhyNot: the discarded rounds are not an optimisation. On the JVM the first runs are interpreted
/// and measure the compiler warming up, not the code. Without them every number here is 5-20x too
/// large and the comparison between cases is meaningless.
///
def iterations(): Int32 = 20000
def rounds(): Int32 = 7
def warmupRounds(): Int32 = 3

def main(): Unit \ IO =
    let cases = List#{
        ("fields.build",      "Fields.empty() with six values put in",        () -> benchBuild()),
        ("render.json",       "toJsonLine on that record (pure)",             () -> benchRender()),
        ("render.no.fields",   "toJsonLine on a record with no fields",        () -> benchRenderEmpty()),
        ("value.one.string",   "valueToJsonString on a single string",         () -> benchValueString()),
        ("emit.silent",       "one line through runWithMin into Sink.silent", () -> benchEmit()),
        ("emit.json",         "one line through runWithMin into Sink.json",   () -> benchEmitJson()),
        ("drop.below.min",    "debugWith below the threshold (never built)",  () -> benchDropped()),
        ("exception.fields",  "Logfx.exception on a caught exception",        () -> benchException()),
        ("time.text",         "epoch millis to ISO 8601",                     () -> benchTimeText())
    };
    List.forEach(match (name, what, body) -> report(name, what, measure(body)), cases)

// ---- The cases ----

/// Builds the fields a request line carries. Returns something so nothing is optimised away.
def benchBuild(): Int32 \ IO =
    checked_ecast(Map.size(sampleFields()))

/// Renders a record as one line of JSON, without touching IO.
def benchRender(): Int32 \ IO =
    checked_ecast(String.length(Logfx.toJsonLine(1757300000123i64, sampleRecord())))

/// The same, with nothing but time / severity / message. Tells how much of the cost is per field.
def benchRenderEmpty(): Int32 \ IO =
    checked_ecast(String.length(Logfx.toJsonLine(1757300000123i64,
        { severity = Logfx.Severity.Info, message = "request finished", fields = Logfx.Fields.empty() })))

/// One value through the JSON encoder, which toJsonLine calls once per key and once per value.
def benchValueString(): Int32 \ IO =
    checked_ecast(String.length(Logfx.valueToJsonString(Logfx.Value.Str("/posts"))))

/// The whole path a line takes, with a sink that writes nothing.
def benchEmit(): Int32 \ IO =
    Logfx.runWithMin(Logfx.Severity.Info, Logfx.Sink.silent(), () -> {
        Logfx.info("request finished", sampleFields());
        1
    })

/// The same path, rendering the JSON and handing the string to a sink that keeps its length.
def benchEmitJson(): Int32 \ IO =
    let seen = Ref.fresh(Static, 0);
    let sink = Logfx.Sink.json(() -> checked_ecast(1757300000123i64), line -> Ref.put(String.length(line), seen));
    Logfx.runWithMin(Logfx.Severity.Info, sink, () -> Logfx.info("request finished", sampleFields()));
    Ref.get(seen)

/// A line the threshold drops. The fields are never built, which is the point being measured.
def benchDropped(): Int32 \ IO =
    Logfx.runWithMin(Logfx.Severity.Info, Logfx.Sink.silent(), () -> {
        Logfx.debugWith("query plan", () -> sampleFields());
        1
    })

/// Copying a caught exception into fields: the cause chain and the frame filter.
def benchException(): Int32 \ IO =
    Map.size(Logfx.Fields.empty() |> Logfx.exception(caught()))

/// The hand-written calendar arithmetic.
def benchTimeText(): Int32 \ IO =
    checked_ecast(String.length(Logfx.timeText(1757300000123i64)))

// ---- Fixtures ----

/// The fields of a request line: two strings, two numbers, a boolean, a list.
def sampleFields(): Logfx.Fields =
    Logfx.Fields.empty()
        |> Logfx.Fields.str("http.request.method", "GET")
        |> Logfx.Fields.str("url.path", "/posts")
        |> Logfx.Fields.int("http.response.status_code", 200i64)
        |> Logfx.Fields.float("duration.ratio", 0.5)
        |> Logfx.Fields.bool("cache.hit", true)
        |> Logfx.Fields.strs("error.codes", List#{"NONE"})

def sampleRecord(): Logfx.Record =
    { severity = Logfx.Severity.Info, message = "request finished", fields = sampleFields() }

/// An exception that has actually been thrown, so it carries a real stack trace.
def caught(): Throwable \ IO =
    try {
        checked_cast(new RuntimeException("not thrown"))
    } catch {
        case error: IllegalStateException => checked_cast(error)
    }

// ---- The harness ----

///
/// Runs the thunk `iterations()` times per round and answers the nanoseconds each round took,
/// oldest first, with the warm-up rounds already dropped.
///
/// WhyNot: the mean is not reported. One round in seven lands on a garbage collection and pulls a
/// mean far away from what a line normally costs. The median says what usually happens and the
/// fastest round says what the code can do; the pair is enough to see a regression.
///
def measure(thunk: Unit -> Int32 \ IO): List[Int64] \ IO =
    let total = warmupRounds() + rounds();
    List.range(0, total)
        |> List.map(_round -> oneRound(thunk))
        |> List.drop(warmupRounds())

def oneRound(thunk: Unit -> Int32 \ IO): Int64 \ IO =
    let startedAt = System.nanoTime();
    let sunk = repeat(thunk, iterations(), 0);
    let elapsed = System.nanoTime() - startedAt;
    // WhyNot: the accumulator is not discarded. Something has to depend on the result, or the
    // whole loop is free to disappear.
    if (sunk == -1) 0i64 else elapsed

def repeat(thunk: Unit -> Int32 \ IO, left: Int32, acc: Int32): Int32 \ IO =
    if (left <= 0) acc else repeat(thunk, left - 1, acc + thunk())

// ---- Reporting ----

/// One JSON object per case: the median and the fastest round, as nanoseconds per iteration.
def report(name: String, what: String, roundsTaken: List[Int64]): Unit \ IO =
    let per = roundsTaken |> List.map(elapsed -> elapsed / Int32.toInt64(iterations()));
    let sorted = List.sort(per);
    let median = List.nth(List.length(sorted) / 2, sorted) |> Option.getWithDefault(0i64);
    let fastest = List.minimum(sorted) |> Option.getWithDefault(0i64);
    println("{\"case\":\"${name}\",\"ns_median\":${median},\"ns_fastest\":${fastest},\"iterations\":${iterations()},\"rounds\":${rounds()},\"what\":\"${what}\"}")

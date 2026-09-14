//
// Logfx: structured logging. The caller emits a line through an effect (Logfx); where it goes is
// a value (Sink). Nothing outside the JDK is required, and nothing here knows the application.
//
// - A line is a Record (severity / message / fields). Sink.json renders it (toJsonLine)
// - A span is withFields (nested handlers; the inner one wins)
// - runWith(sink, thunk) at the entry of a thread. The sink is a value, so it crosses a spawn
// - Tests use runWithList
//
// WhyNot: the head of the file is not ///, because an import after /// fails to compile.

///
/// The logging effect. `emit` writes one line; `enabled` asks whether a severity is worth building.
///
/// WhyNot: do not add operations later. The effect is `pub`, so anyone can write a handler,
/// and one more operation breaks every hand-written one. `enabled` landed in 0.2.0,
/// while there were no users at all.
///
pub eff Logfx {
    /// Writes one line.
    def emit(record: Logfx.Record): Unit
    /// Whether this severity is emitted. On `false` the caller may skip building the fields.
    def enabled(severity: Logfx.Severity): Bool
}

mod Logfx {
    import java.lang.StackTraceElement
    import java.lang.Throwable

    use Util.Json.Json
    use Util.Json.Json.{JNull, JBool, JNumber, JString, JArray, JObject}
   // The value type and its JSON rendering live in this same module


    ///
    /// What a log field holds. The same shape as JSON.
    ///
    /// WhyNot: do not take the caller's JSON type. A logging library that depends on the
    /// caller's types inverts the dependency and cannot be extracted. Convert at your own boundary.
    ///
    /// WhyNot: do not put a type named `Value` at the top level. Flix cannot hide modules,
    /// so it would collide with the caller's own `Value` (GraphQL, JSON) and make the library unusable.
    ///
    pub enum Value with Eq, ToString {
        /// null
        case Null
        /// true / false
        case Bool(Bool)
        /// An integer (`Int64`).
        ///
        /// WhyNot: not `Int32`. Byte counts and accumulated microseconds pass 2 GB. Clamping them
        /// silently prints 2147483647 with nothing to tell the reader the value broke
        /// (the same reason `floatJson` does not turn `NaN` into 0).
        ///
        case Int(Int64)
        /// A float.
        case Float(Float64)
        /// A string.
        case Str(String)
        /// A list.
        case List(List[Value])
        /// Key to value.
        case Obj(Map[String, Value])
    }

    ///
    /// The string, if it is one.
    ///
    /// WhyNot: do not ship only `valueAsStr`. Whoever writes a sink dispatches on the fields,
    /// and a single accessor leaves them guessing whether the rest are missing or deliberately
    /// left to `match`. There is one per case.
    ///
    pub def valueAsStr(value: Value): Option[String] = match value {
        case Value.Str(s) => Some(s)
        case _            => None
    }

    ///
    /// The integer, if it is one.
    ///
    pub def valueAsInt(value: Value): Option[Int64] = match value {
        case Value.Int(n) => Some(n)
        case _            => None
    }

    ///
    /// The float, if it is one. An integer is not converted: a difference in type stays visible.
    ///
    pub def valueAsFloat(value: Value): Option[Float64] = match value {
        case Value.Float(x) => Some(x)
        case _              => None
    }

    ///
    /// The boolean, if it is one.
    ///
    pub def valueAsBool(value: Value): Option[Bool] = match value {
        case Value.Bool(b) => Some(b)
        case _             => None
    }

    ///
    /// The list, if it is one.
    ///
    pub def valueAsList(value: Value): Option[List[Value]] = match value {
        case Value.List(items) => Some(items)
        case _                 => None
    }

    ///
    /// The object, if it is one.
    ///
    pub def valueAsObj(value: Value): Option[Map[String, Value]] = match value {
        case Value.Obj(fields) => Some(fields)
        case _                 => None
    }

    ///
    /// Whether the value is null.
    ///
    pub def valueIsNull(value: Value): Bool = match value {
        case Value.Null => true
        case _          => false
    }

    ///
    /// Renders the value as a JSON fragment.
    ///
    pub def valueToJsonString(value: Value): String =
        Util.Json.toCompactString(valueToJson(value))

    ///
    /// Converts to `Util.Json.Json`.
    ///
    pub def valueToJson(value: Value): Json = match value {
        case Value.Null        => JNull
        case Value.Bool(b)     => JBool(b)
        case Value.Int(n)      => JNumber(Int64.toBigDecimal(n))
        case Value.Float(x)    => floatJson(x)
        case Value.Str(s)      => JString(s)
        case Value.List(items) => JArray(List.map(valueToJson, items) |> List.toVector)
        case Value.Obj(fields) => JObject(Map.map(valueToJson, fields))
    }

    ///
    /// WhyNot: `NaN` and the infinities are not turned into 0. That would hide from the reader
    /// that a measurement broke. JSON has no way to write them, so they become null.
    ///
    def floatJson(x: Float64): Json =
        if (Float64.isNan(x) or Float64.isInfinite(x)) JNull
        else BigDecimal.fromString(ToString.toString(x)) |> Option.map(JNumber) |> Option.getWithDefault(JNull)

    ///
    /// How heavy a line is. Trace < Debug < Info < Warn < Error < Fatal.
    ///
    pub enum Severity with Eq, Order, ToString {
        case Trace
        case Debug
        case Info
        case Warn
        case Error
        case Fatal
    }

    ///
    /// The attributes on a line. Keys follow the OpenTelemetry semantic conventions
    /// (`http.request.method`, and so on).
    ///
    /// WhyNot: `Value` rather than an enum of its own, so rendering JSON needs no conversion
    /// and there is one place to change when the representation moves.
    ///
    pub type alias Fields = Map[String, Value]

    ///
    /// One log line.
    ///
    /// - severity: how heavy the line is
    /// - message: a short sentence for a human
    /// - fields: the attributes
    ///
    pub type alias Record = { severity = Severity, message = String, fields = Fields }

    ///
    /// Where lines go: a function that takes a `Record` and writes it. The same role as
    /// slog's Handler, and a plain value, so it crosses threads.
    ///
    pub type alias Sink = Record -> Unit \ IO

    // ---- The calling side ----

    ///
    /// Emits one line at the given severity. Does nothing when `enabled` answers false.
    ///
    pub def log(severity: Severity, message: String, fields: Fields): Unit \ Logfx =
        if (Logfx.enabled(severity)) Logfx.emit({ severity = severity, message = message, fields = fields }) else ()

    ///
    /// Emits one line at the given severity. The fields are built only when `enabled` answers true.
    ///
    /// WhyNot: `log(severity, message, fields)` is not enough. There the fields are already built
    /// at the call site, so every `Map.insert` runs even for a line that is dropped. The same reason
    /// Go's slog has a separate `Enabled()`: building has to go behind a thunk.
    ///
    pub def logWith(severity: Severity, message: String, build: Unit -> Fields \ ef): Unit \ ef + Logfx =
        if (Logfx.enabled(severity)) Logfx.emit({ severity = severity, message = message, fields = build() }) else ()

    /// Emits a Trace line. The fields come last, so they pipe.
    pub def trace(message: String, fields: Fields): Unit \ Logfx =
        log(Severity.Trace, message, fields)

    /// Emits a Debug line.
    pub def debug(message: String, fields: Fields): Unit \ Logfx =
        log(Severity.Debug, message, fields)

    /// Emits an Info line.
    pub def info(message: String, fields: Fields): Unit \ Logfx =
        log(Severity.Info, message, fields)

    /// Emits a Warn line.
    pub def warn(message: String, fields: Fields): Unit \ Logfx =
        log(Severity.Warn, message, fields)

    /// Emits an Error line.
    pub def error(message: String, fields: Fields): Unit \ Logfx =
        log(Severity.Error, message, fields)

    /// Emits a Fatal line.
    pub def fatal(message: String, fields: Fields): Unit \ Logfx =
        log(Severity.Fatal, message, fields)

    /// Emits a Trace line. The fields are built only if the line is emitted.
    pub def traceWith(message: String, build: Unit -> Fields \ ef): Unit \ ef + Logfx =
        logWith(Severity.Trace, message, build)

    /// Emits a Debug line. The fields are built only if the line is emitted.
    pub def debugWith(message: String, build: Unit -> Fields \ ef): Unit \ ef + Logfx =
        logWith(Severity.Debug, message, build)

    /// Emits an Info line. The fields are built only if the line is emitted.
    pub def infoWith(message: String, build: Unit -> Fields \ ef): Unit \ ef + Logfx =
        logWith(Severity.Info, message, build)

    /// Emits a Warn line. The fields are built only if the line is emitted.
    pub def warnWith(message: String, build: Unit -> Fields \ ef): Unit \ ef + Logfx =
        logWith(Severity.Warn, message, build)

    /// Emits an Error line. The fields are built only if the line is emitted.
    pub def errorWith(message: String, build: Unit -> Fields \ ef): Unit \ ef + Logfx =
        logWith(Severity.Error, message, build)

    /// Emits a Fatal line. The fields are built only if the line is emitted.
    pub def fatalWith(message: String, build: Unit -> Fields \ ef): Unit \ ef + Logfx =
        logWith(Severity.Fatal, message, build)

    ///
    /// Adds a Java exception to the fields as `exception.type` / `exception.message` /
    /// `exception.cause` / `exception.stacktrace`.
    ///
    /// - message: trimmed to 200 characters, with everything from `"Detail:"` onwards dropped. Empty when null.
    /// - cause: `getCause` followed up to 3 links, each rendered `"type: message"` and joined with `" <- "`.
    ///   Absent when there is no cause.
    /// - stacktrace: the Flix frames only (class name containing `Def$` or `Clo$`), at most 8,
    ///   each written `class.method(file:line)` and joined with `" | "`.
    ///
    /// WhyNot: the message is not printed whole, because PostgreSQL puts the offending row
    /// (a key, an email address) after `Detail:`.
    /// WhyNot: not every frame, because `dev.flix.runtime` and JDK frames do not say where you are,
    /// and on the day the database falls over they pile up 3 KB per line.
    /// WhyNot: not the frame's own `toString`, which spells the file as the absolute path it was
    /// compiled from. The build machine's directory layout would then ride on every error line,
    /// and it is the same line that multiplies on the day the database falls over.
    /// WhyNot: no frame without a line number. `Clo$…invoke` frames carry the file but not the line,
    /// so they cost bytes without saying where you are.
    /// WhyNot: not the outermost exception alone. JDBC and HTTP both wrap the real reason
    /// (connection refused, a certificate), so the outside leaves you with "a SQLException happened"
    /// and not one line of cause.
    /// WhyNot: the cause chain is not followed without a limit. Three links reach the real reason
    /// and stop on a cause that cycles.
    /// WhyNot: not separated by newlines. `toJsonLine` strips control characters (log injection),
    /// so newlines would run every frame together into one word.
    ///
    pub def exception(error: Throwable, fields: Fields): Fields \ IO =
        let message: String = error.getMessage();
        let causes = causeChain(error.getCause(), 3);
        fields
            |> Fields.str("exception.type", error.getClass().getName())
            |> Fields.str("exception.message", if (Object.isNull(message)) "" else shortMessage(message))
            |> Fields.opt("exception.cause", if (List.isEmpty(causes)) None else Some(List.join(" <- ", causes)))
            |> Fields.str("exception.stacktrace", flixFrames(error) |> List.join(" | "))

    /// Renders the `getCause` chain as `"type: message"`, up to `budget` links. Stops at null.
    def causeChain(error: Throwable, budget: Int32): List[String] \ IO =
        if (budget <= 0 or Object.isNull(error)) Nil
        else {
            let message: String = error.getMessage();
            let text = "${error.getClass().getName()}: ${if (Object.isNull(message)) "" else shortMessage(message)}";
            let next: Throwable = error.getCause();
            text :: causeChain(next, budget - 1)
        }

    /// Takes what comes before `"Detail:"`, trims it, and cuts it to 200 characters.
    def shortMessage(message: String): String =
        String.splitOn(substr = "Detail:", message) |> List.head |> Option.getWithDefault("") |> String.trim |> String.takeLeft(200)

    /// The Flix frames that know their line, at most 8.
    def flixFrames(error: Throwable): List[String] \ IO =
        Array.toList(error.getStackTrace())
            |> List.filter(frame -> {
                let className: String = frame.getClassName();
                (String.contains(substr = "Def$", className) or String.contains(substr = "Clo$", className))
                    and frame.getLineNumber() > 0
            })
            |> List.take(8)
            |> List.map(frameText)

    /// One frame as `class.method(file:line)`.
    def frameText(frame: StackTraceElement): String \ IO =
        "${frame.getClassName()}.${frame.getMethodName()}(${fileName(frame.getFileName())}:${frame.getLineNumber()})"

    /// The last segment of a path. Empty when null.
    def fileName(path: String): String =
        if (Object.isNull(path)) ""
        else String.splitOn(substr = "/", path) |> List.last |> Option.getWithDefault(path)

    // ---- Spans and handlers ----

    ///
    /// A scope (span): every line emitted inside the thunk carries the fields. The line's own
    /// fields win over these, and an inner `withFields` wins over an outer one.
    /// The fields come first so it partially applies as `run { ... } with Logfx.withFields(fields)`.
    ///
    pub def withFields(fields: Fields, thunk: Unit -> a \ ef): a \ (ef - Logfx) + Logfx =
        run {
            thunk()
        } with handler Logfx {
            def emit(record, k) = {
                Logfx.emit({ severity = record#severity, message = record#message, fields = Map.union(record#fields, fields) });
                k()
            }
            def enabled(severity, k) = k(Logfx.enabled(severity))
        }

    ///
    /// The entry point of a thread. Passes every severity to the sink.
    /// Use `runWithMin` to drop the lighter lines.
    ///
    pub def runWith(sink: Sink, thunk: Unit -> a \ ef): a \ (ef - Logfx) + IO =
        runWithMin(Severity.Trace, sink, thunk)

    ///
    /// The entry point of a thread. Lines below `min` get `false` from `enabled` and never reach
    /// the sink (`min` itself is kept).
    ///
    /// WhyNot: an exception from the sink does not reach the caller. At the point the effect operation
    /// runs, the thunk's frames are already unwound, so a throw would sail past the caller's `catch`
    /// and skip the transaction cleanup. A failure to log must not take the request down.
    /// `Sink.fallback` is where a broken sink gets told to the operator instead.
    ///
    /// WhyNot: the severity test is not left to `Sink.minSeverity` alone. Dropping the line at the sink
    /// means the fields were built anyway. Answering in the handler lets `logWith` / `infoWith`
    /// skip the building too.
    ///
    pub def runWithMin(min: Severity, sink: Sink, thunk: Unit -> a \ ef): a \ (ef - Logfx) + IO =
        run {
            thunk()
        } with handler Logfx {
            def emit(record, k) = {
                try {
                    sink(record)
                } catch {
                    case _: Throwable => ()
                };
                k()
            }
            def enabled(severity, k) = k(Order.greaterEqual(severity, min))
        }

    ///
    /// For tests. Collects the lines and returns them with the thunk's result, oldest first.
    ///
    pub def runWithList(thunk: Unit -> a \ ef): (a, List[Record]) \ (ef - Logfx) =
        run {
            (thunk(), Nil)
        } with handler Logfx {
            def emit(record, k) = {
                let (result, rest) = k();
                (result, record :: rest)
            }
            def enabled(_severity, k) = k(true)
        }

    // ---- One line of JSON ----

    ///
    /// Renders a `Record` as one line of JSON. `time` / `severity` / `message` come first,
    /// the rest in key order. `time` is ISO 8601 UTC with milliseconds always present (`.000Z` too);
    /// `severity` is lower case. Control characters are stripped from every string in the fields.
    ///
    /// WhyNot: `time` / `severity` / `message` in the fields are dropped, because the same key twice
    /// leaves it up to the reader of the JSON which one survives.
    /// WhyNot: control characters are not left to JSON escaping. A newline would not split the line,
    /// but a terminal escape sequence passes through and can forge one (log injection).
    ///
    pub def toJsonLine(timeMillis: Int64, record: Record): String =
        let head = List#{("time", Value.Str(timeText(timeMillis))), ("severity", Value.Str(severityText(record#severity))), ("message", Value.Str(record#message))};
        let rest = record#fields |> Map.remove("time") |> Map.remove("severity") |> Map.remove("message") |> Map.toList;
        List.append(head, rest)
            |> List.map(match (key, value) -> "${Logfx.valueToJsonString(Value.Str(key))}:${Logfx.valueToJsonString(withoutControlChars(value))}")
            |> List.join(",")
            |> body -> "{${body}}"

    ///
    /// A `Severity` from a configuration string (`LOG_LEVEL`, and so on). Case insensitive.
    /// An unknown word is `None`.
    ///
    pub def parseSeverity(text: String): Option[Severity] = match String.toLowerCase(String.trim(text)) {
        case "trace" => Some(Severity.Trace)
        case "debug" => Some(Severity.Debug)
        case "info"  => Some(Severity.Info)
        case "warn"  => Some(Severity.Warn)
        case "error" => Some(Severity.Error)
        case "fatal" => Some(Severity.Fatal)
        case _       => None
    }

    /// The JSON value for a severity.
    def severityText(severity: Severity): String = match severity {
        case Severity.Trace => "trace"
        case Severity.Debug => "debug"
        case Severity.Info  => "info"
        case Severity.Warn  => "warn"
        case Severity.Error => "error"
        case Severity.Fatal => "fatal"
    }

    /// Strips control characters from strings, recursing into lists and objects.
    def withoutControlChars(value: Value): Value = match value {
        case Value.Str(text)    => Value.Str(String.replaceMatches(regex = "\\p{Cntrl}", to = "", text))
        case Value.List(items)  => Value.List(List.map(withoutControlChars, items))
        case Value.Obj(fields)  => Value.Obj(Map.map(withoutControlChars, fields))
        case other              => other
    }

    ///
    /// Epoch milliseconds as ISO 8601 UTC (`yyyy-MM-ddTHH:mm:ss.SSSZ`). Negative values are before 1970.
    ///
    /// WhyNot: not `java.time`, which would be 5 lines instead of 40. Two reasons.
    /// Effects: a Java call is `\ IO`, so `toJsonLine` and `timeText` would become `IO` too, and the
    /// shape of a line could no longer be checked as a pure function in a table
    /// (the boundary where only the sink is `IO` would break).
    /// Output: `DateTimeFormatter.ISO_INSTANT` drops `".000"` when the milliseconds are zero,
    /// mixing widths into the `time` field. A log backend reads the timestamp by its shape,
    /// so it cannot move.
    /// The calendar arithmetic itself is Howard Hinnant's `civil_from_days`; leap days, year 9999
    /// and negative times are pinned down in a table test.
    ///
    pub def timeText(timeMillis: Int64): String =
        let days = floorDiv(timeMillis, 86400000i64);
        let msOfDay = timeMillis - days * 86400000i64;
        let (year, month, day) = civilOf(days);
        let hour = msOfDay / 3600000i64;
        let minute = (msOfDay / 60000i64) - hour * 60i64;
        let second = (msOfDay / 1000i64) - (msOfDay / 60000i64) * 60i64;
        let millis = msOfDay - (msOfDay / 1000i64) * 1000i64;
        "${pad(4, year)}-${pad(2, month)}-${pad(2, day)}T${pad(2, hour)}:${pad(2, minute)}:${pad(2, second)}.${pad(3, millis)}Z"

    /// Division that rounds towards negative infinity (`divisor` is positive).
    def floorDiv(dividend: Int64, divisor: Int64): Int64 =
        let quotient = dividend / divisor;
        if (dividend - quotient * divisor < 0i64) quotient - 1i64 else quotient

    /// Days since the epoch as (year, month, day), Gregorian.
    def civilOf(days: Int64): (Int64, Int64, Int64) =
        let z = days + 719468i64;
        let era = floorDiv(z, 146097i64);
        let dayOfEra = z - era * 146097i64;
        let yearOfEra = (dayOfEra - dayOfEra / 1460i64 + dayOfEra / 36524i64 - dayOfEra / 146096i64) / 365i64;
        let dayOfYear = dayOfEra - (365i64 * yearOfEra + yearOfEra / 4i64 - yearOfEra / 100i64);
        let monthIndex = (5i64 * dayOfYear + 2i64) / 153i64;
        let day = dayOfYear - (153i64 * monthIndex + 2i64) / 5i64 + 1i64;
        let month = if (monthIndex < 10i64) monthIndex + 3i64 else monthIndex - 9i64;
        let year = yearOfEra + era * 400i64 + (if (month <= 2i64) 1i64 else 0i64);
        (year, month, day)

    /// A zero-padded number.
    def pad(width: Int32, n: Int64): String = String.padLeft(width, '0', Int64.toString(n))

}

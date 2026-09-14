///
/// Composing sinks. Every one of them is built by a `def`.
///
/// WhyNot: a lambda literal is not put in a `let` and then used on both sides of a `spawn`,
/// because effect inference fails there.
///
mod Logfx.Sink {
    import java.lang.Throwable

    use Logfx.Severity

    /// Passes one line of JSON to `out`. The time is read from `clock` per line.
    pub def json(clock: Unit -> Int64 \ IO, out: String -> Unit \ IO): Logfx.Sink =
        record -> out(Logfx.toJsonLine(clock(), record))

    /// Drops lines lighter than `min` (`min` itself is kept).
    pub def minSeverity(min: Severity, next: Logfx.Sink): Logfx.Sink =
        record -> if (Order.greaterEqual(record#severity, min)) next(record) else ()

    /// Adds fields to every line (`service`, `version`). The line's and the span's fields win.
    pub def enrich(fields: Logfx.Fields, next: Logfx.Sink): Logfx.Sink =
        record -> next({ severity = record#severity, message = record#message, fields = Map.union(record#fields, fields) })

    ///
    /// Passes the same line to two sinks (stdout and a collector, say).
    ///
    /// Both sinks are always called. If either throws, the first exception is rethrown once both
    /// have run, so `runWith` swallows it or an enclosing `fallback` picks it up.
    ///
    /// WhyNot: the caller does not write `record -> (a(record); b(record))`. As the head of this file
    /// says, effect inference on a lambda literal fails in places, and one value here is reliable.
    /// WhyNot: a throw from `first` does not skip `second`. The worst day is the one where one sink
    /// breaks and silences the other too.
    ///
    pub def tee(first: Logfx.Sink, second: Logfx.Sink): Logfx.Sink =
        record -> {
            let firstError = attempt(first, record);
            let secondError = attempt(second, record);
            match (if (Option.isEmpty(firstError)) secondError else firstError) {
                case Some(error) => throw error
                case None        => ()
            }
        }

    ///
    /// Passes the line to `secondary` when `primary` throws. The line that reaches `secondary`
    /// carries `logfx.fallback_reason`, naming the exception that killed `primary`.
    ///
    /// WhyNot: no `onError` on `runWith`. Every user would end up writing one, and it can throw
    /// itself, which needs another layer of `catch`. What an operator wants is not a notification
    /// but the line that went missing, so "where a broken sink writes instead" is spelled as
    /// sink composition, the same type as `minSeverity` / `enrich` / `tee`.
    /// When `secondary` throws too, `runWith` drops it: at that point there is nowhere left to write.
    ///
    pub def fallback(primary: Logfx.Sink, secondary: Logfx.Sink): Logfx.Sink =
        record -> match attempt(primary, record) {
            case None        => ()
            case Some(error) =>
                let reason = "${error.getClass().getName()}: ${reasonText(error)}";
                secondary({ severity = record#severity, message = record#message,
                            fields = Logfx.Fields.str("logfx.fallback_reason", reason, record#fields) })
        }

    /// Passes the record to the sink and returns whatever it threw.
    def attempt(sink: Logfx.Sink, record: Logfx.Record): Option[Throwable] \ IO =
        try {
            sink(record);
            None
        } catch {
            case error: Throwable => Some(error)
        }

    /// The exception's message. Empty when null.
    def reasonText(error: Throwable): String =
        let message: String = error.getMessage();
        if (Object.isNull(message)) "" else message

    ///
    /// Writes nothing. For the places that need a sink but no output.
    ///
    /// WhyNot: not written `_ -> ()`. Passing a pure lambda where a `\ IO` function type is expected
    /// needs `--Xsubeffecting=lambdas`, which is experimental. Callers build with a plain `flix`,
    /// so a library must never demand an experimental flag.
    ///
    pub def silent(): Logfx.Sink =
        _ -> checked_ecast(())

    /// For tests. Pushes lines onto a `Ref`, newest first. Usable from inside a `spawn`.
    pub def collect(sink: Ref[List[Logfx.Record], Static]): Logfx.Sink =
        record -> Ref.put(record :: Ref.get(sink), sink)

}

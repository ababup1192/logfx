///
/// Work that no request is waiting for. It runs on its own thread and still needs to say which
/// request it came from.
///
/// WhyNot: the span is not carried by Logfx.withFields. An effect handler does not cross a thread,
/// so a job spawned inside a withFields scope cannot reach it. What crosses is the sink, which is
/// a plain value, so the span travels as Sink.enrich — see Server.spawnJobs.
///
mod Jobs {

    use Logfx.Fields

    /// Performs one job and says how it went. It only logs, so the effect is `\ Logfx` alone.
    pub def perform(kind: String): Unit \ Logfx =
        Fields.empty()
            |> Fields.str("job.kind", kind)
            |> Fields.str("job.outcome", "done")
            |> Logfx.info("job done")

}

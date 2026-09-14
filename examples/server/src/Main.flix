import java.lang.System

///
/// サーバの入口。logfx について決める事は全部ここに集まる（どこへ書くか、壊れた時どこへ逃がすか、
/// 全行に何を足すか、どの段から出すか）。
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
/// サーバの配線。Sink を組み、段を決め、リクエストごとに handler を置く。
///
/// WhyNot: main を丸ごと 1 つの runWithMin で包んで、その中で spawn しない。Logfx は effect
/// なので handler はスレッドを越えず、spawn の中で Logfx.info を呼ぶと
/// 「Unable to unify the effect formulas: 'Logfx' and '(Chan + IO + NonDet) & e0'」で落ちる。
/// 越えるのは Sink の方で、値なのでそのまま渡せる。
///
mod Server {

    use Logfx.Fields
    use Logfx.Severity

    import java.lang.System

    // ---- 配線 ----

    ///
    /// 全リクエストが共有する 1 本の Sink。enrich で全行に service.* を足し、fallback で
    /// stdout が壊れた日の行き先を stderr にする（logfx.fallback_reason 付き）。
    ///
    /// WhyNot: リクエストごとに作らない。Sink は値で、持ち回る状態が無い。
    ///
    pub def sink(): Logfx.Sink =
        let service = Fields.empty()
            |> Fields.str("service.name", "example-server")
            |> Fields.str("service.version", "0.0.0");
        let toStdout = Logfx.Sink.json(_ -> System.currentTimeMillis(), line -> println(line));
        let toStderr = Logfx.Sink.json(_ -> System.currentTimeMillis(), line -> System.err.println(line));
        Logfx.Sink.enrich(service, Logfx.Sink.fallback(toStdout, toStderr))

    ///
    /// LOG_LEVEL から段を読む。無い時と知らない語は Info。
    ///
    /// WhyNot: 知らない語で落とさない。設定の綴り違いでサーバが起動しない方が、
    /// 1 段ずれてログが出る事より高く付く。
    ///
    /// WhyNot: 段の判定を Sink.minSeverity に任せない。sink まで行ってから捨てると、捨てる行でも
    /// fields は組み上がっている。runWithMin なら debugWith が組み立てごと飛ばせる。
    ///
    pub def minSeverity(): Severity \ IO =
        let text: String = System.getenv("LOG_LEVEL");
        if (Object.isNull(text)) Severity.Info
        else Logfx.parseSeverity(text) |> Option.getWithDefault(Severity.Info)

    /// 受け口の代わり。(request.id, method, path) を順に流す。
    pub def incoming(): List[(String, String, String)] =
        List#{("r1", "GET", "/health"), ("r2", "GET", "/posts"), ("r3", "GET", "/nope")}

}

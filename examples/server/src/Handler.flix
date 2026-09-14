///
/// リクエスト 1 本の処理。利用側が普段書く場所で、Sink も handler も出てこない。
///
/// WhyNot: ここで runWith を呼ばない。呼ぶと出力先がこの関数に焼き付いて、テストから差し替え
/// られなくなる。handler はスレッドの入口（Server）に 1 つだけ置く。
///
/// WhyNot: logger を引数で受け取らない。Logfx は effect なので、受け渡しは呼び出しの連鎖では
/// なく handler が持つ。引数で配ると、経路の途中の関数が全部それを知る事になる。
///
mod Handler {

    use Logfx.Fields

    import java.lang.RuntimeException
    import java.lang.Throwable

    // ---- 入口 ----

    ///
    /// リクエスト 1 本を処理して HTTP の status を返す。
    ///
    /// 効果は `{IO, Logfx}`。`Logfx` はログを出すから、`IO` は仕事の方が触るから付く。
    /// 行がどこへ出るかは、この `Logfx` を handle する側（Server）が決める。
    ///
    pub def handle(requestId: String, method: String, path: String): Int32 \ {IO, Logfx} =
        run {
            route(path)
        } with Logfx.withFields(span(requestId, method, path))

    ///
    /// リクエストの span。中で出る行すべてに付く。
    ///
    /// WhyNot: path をそのままキーにしても基数は上がらない（url.path は OTel の名前で、
    /// 集計に使うのは route.pattern の方）。数える側が困るのは pattern が無い時。
    ///
    def span(requestId: String, method: String, path: String): Fields =
        Fields.empty()
            |> Fields.str("request.id", requestId)
            |> Fields.str("http.request.method", method)
            |> Fields.str("url.path", path)

    // ---- 経路 ----

    /// 経路ごとの処理。span の中なので、ここで出る行には request.id などが必ず付く。
    def route(path: String): Int32 \ {IO, Logfx} =
        // 重い行は、その段が有効な時だけ組み立てる（debugWith の thunk は enabled が true の時しか走らない）。
        Logfx.debugWith("routing", () -> Fields.empty() |> Fields.str("route.pattern", pattern(path)));
        match path {
            case "/posts"  => listPosts()
            case "/health" => 200
            case _         =>
                Logfx.warn("no route", Fields.empty());
                404
        }

    /// 記事の一覧。数えた物は Int32.toInt64 で渡す（Fields.int は Int64）。
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
                // Logfx.exception は fields を足す関数なので、そのままパイプの途中に入る。
                Fields.empty()
                    |> Fields.int("http.response.status_code", 500i64)
                    |> Logfx.exception(error)
                    |> Logfx.error("request failed");
                500
        }

    /// path から経路の形。
    def pattern(path: String): String =
        if (String.startsWith(prefix = "/posts", path)) "/posts" else path

    ///
    /// DB の代わり。呼ぶたびに投げる。
    ///
    /// WhyNot: 成功する版を置かない。この例で見せたいのは exception の行なので、
    /// 落ちる経路が 1 本要る。
    ///
    def fetchPosts(): List[String] \ IO =
        throw new RuntimeException("connection refused")

}

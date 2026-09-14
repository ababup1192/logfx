//
// README の最初のコード片、そのままの物。
//
// WhyNot: README のコードをここに写すのではなく、ここが本体で README が写し。README の
// コードは誰もコンパイルしないので、先に腐るのは必ず README の方。ci/example.sh がここを
// 毎回ビルドするので、腐ったら赤くなる。
//
import java.lang.System

///
/// 利用側のコードが取るのは effect であって logger ではない。どこへ出るかはここで決めない。
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

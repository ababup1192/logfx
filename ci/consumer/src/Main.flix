//
// まっさらなプロジェクトから見た logfx。取り込んだ版が実際に動く事だけを見る。
// 時刻は固定（出力を 1 行ずつ比べるため）。
//
// WhyNot: logfx のテストをここで焼き直さない。ここで見たいのは「パッケージとして取り込めるか」
// （security の設定、実験フラグ無しで通るか、公開している名前が外から見えるか）だけ。
//

import java.lang.ArithmeticException
import java.lang.RuntimeException
import java.lang.Throwable

/// いつも同じ時刻（2025-09-08T02:53:20.123Z）。
def clock(): Int64 \ IO = checked_ecast(1757300000123i64)

/// 必ず投げる sink。fallback の primary に使う。
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
    // 壊れた sink の行が secondary に落ちて、理由が付く。
    Logfx.runWith(Logfx.Sink.fallback(brokenSink, Logfx.Sink.tee(Logfx.Sink.silent(), sink)), () ->
        Logfx.Fields.empty() |> Logfx.warn("primary is down"))

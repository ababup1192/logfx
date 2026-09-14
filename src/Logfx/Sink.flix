///
/// Sink の合成。全部 def で作る。
///
/// WhyNot: lambda literal を let に置いて spawn の内外で使わないのは、effect の推論で落ちるため。
///
mod Logfx.Sink {
    import java.lang.Throwable

    use Logfx.Severity

    /// 1 行 JSON を out に渡す。時刻は clock で行ごとに取る。
    pub def json(clock: Unit -> Int64 \ IO, out: String -> Unit \ IO): Logfx.Sink =
        record -> out(Logfx.toJsonLine(clock(), record))

    /// min より軽い行を捨てる（min は残す）。
    pub def minSeverity(min: Severity, next: Logfx.Sink): Logfx.Sink =
        record -> if (Order.greaterEqual(record#severity, min)) next(record) else ()

    /// 全行に fields を足す（service / version）。行と span の fields が勝つ。
    pub def enrich(fields: Logfx.Fields, next: Logfx.Sink): Logfx.Sink =
        record -> next({ severity = record#severity, message = record#message, fields = Map.union(record#fields, fields) })

    ///
    /// 同じ行を 2 つに渡す（標準出力と収集器、など）。
    ///
    /// WhyNot: 利用側で `record -> (a(record); b(record))` と書かせない。このファイルの冒頭の通り
    /// lambda literal の effect の推論で落ちる場所があり、値として 1 本置いた方が確実。
    /// WhyNot: first が投げたら second を飛ばす、にしない。片方が壊れた日にもう片方まで黙るのが
    /// 一番困る。両方に渡してから、最初の例外を投げ直す（runWith が受けるか、fallback が拾う）。
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
    /// primary が投げたら secondary に渡す。secondary の行には logfx.fallback_reason（primary の例外）が付く。
    ///
    /// WhyNot: runWith に onError を足さない。onError は全利用者が 1 つ書く事になり、それ自身が投げうるので
    /// もう 1 枚 catch が要る。運用者が本当に欲しいのは通知ではなく消えた行そのものなので、
    /// 「壊れた時の行き先」を Sink の合成（minSeverity / enrich / tee と同じ型）で書ける方を選ぶ。
    /// secondary も投げた時は runWith が捨てる。そこまで来たら書ける先が無い。
    ///
    pub def fallback(primary: Logfx.Sink, secondary: Logfx.Sink): Logfx.Sink =
        record -> match attempt(primary, record) {
            case None        => ()
            case Some(error) =>
                let reason = "${error.getClass().getName()}: ${reasonText(error)}";
                secondary({ severity = record#severity, message = record#message,
                            fields = Logfx.Fields.str("logfx.fallback_reason", reason, record#fields) })
        }

    /// sink に渡して、投げた例外を返す。
    def attempt(sink: Logfx.Sink, record: Logfx.Record): Option[Throwable] \ IO =
        try {
            sink(record);
            None
        } catch {
            case error: Throwable => Some(error)
        }

    /// 例外の message。null なら空。
    def reasonText(error: Throwable): String =
        let message: String = error.getMessage();
        if (Object.isNull(message)) "" else message

    ///
    /// 何も出さない。テストの Deps など、出力先の要らない所に。
    ///
    /// WhyNot: `_ -> ()` と書かない。純粋なラムダを `\ IO` の関数型に渡すには
    /// --Xsubeffecting=lambdas（experimental）が要る。利用側は素の flix で取り込むので、
    /// ライブラリの側が実験フラグを要求してはいけない。
    ///
    pub def silent(): Logfx.Sink =
        _ -> checked_ecast(())

    /// テスト用。行を Ref に積む（新しい物が先頭）。spawn の中から使える。
    pub def collect(sink: Ref[List[Logfx.Record], Static]): Logfx.Sink =
        record -> Ref.put(record :: Ref.get(sink), sink)

}

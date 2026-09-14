//
// Log: 構造化ログ。呼ぶ側は effect（Log）で行を出し、出力先は値（Sink）で組む。
// 依存は Value / JsonValue だけで、cms / http / app を知らない。
//
// - 行は Record（severity / message / fields）。1 行 JSON にするのは Sink.json（toJsonLine）
// - span は withFields（handler の入れ子。内側が勝つ）
// - スレッドの入口で runWith(sink, thunk)。sink は値なので spawn を跨げる
// - テストは runWithList
//
// WhyNot: ファイル冒頭を /// にしないのは、/// の後に import を置くとコンパイルが落ちるため。
//

///
/// ログの effect。emit で 1 行を出し、enabled でその段を出すかを先に訊く。
///
/// WhyNot: enabled を後から足さない。eff が pub なので handler は誰でも書ける。
/// op が 1 つ増えると、自分で handler を書いた利用者が全員壊れる。利用者が 0 の
/// 0.2.0 で決め切る。
///
pub eff Logfx {
    /// 1 行を出す。
    def emit(record: Logfx.Record): Unit
    /// この段を出すか。false なら呼ぶ側は fields の組み立てごと飛ばしてよい。
    def enabled(severity: Logfx.Severity): Bool
}

mod Logfx {
    import java.lang.Throwable

    use Util.Json.Json
    use Util.Json.Json.{JNull, JBool, JNumber, JString, JArray, JObject}
   // 値の型と JSON 化。Logfx.flix と同じモジュールを開く


    ///
    /// ログのフィールドに入る値。JSON と同じ形。
    ///
    /// WhyNot: 利用側の JSON の型をそのまま受けない。ログのライブラリが利用側の型に依存すると、
    /// 依存の向きが逆になって切り出せなくなる。変換は利用側の境界で書く。
    ///
    /// WhyNot: トップレベルに Value という名前で置かない。Flix はモジュールを隠せないので、
    /// 自分の Value を持つ利用側（GraphQL や JSON を扱うコード）と衝突して使えなくなる。
    ///
    pub enum Value with Eq, ToString {
        /// null
        case Null
        /// true / false
        case Bool(Bool)
        /// 整数（Int64）
        ///
        /// WhyNot: Int32 にしない。バイト数や μs の累計は 2 GB を越える。越えた値を黙って丸めると、
        /// 壊れた事が読む人に伝わらないまま 2147483647 が出る（floatJson が NaN を 0 に倒さないのと同じ理由）。
        ///
        case Int(Int64)
        /// 小数
        case Float(Float64)
        /// 文字列
        case Str(String)
        /// 配列
        case List(List[Value])
        /// キー → 値
        case Obj(Map[String, Value])
    }

    ///
    /// 文字列なら取り出す。
    ///
    /// WhyNot: valueAsStr だけを置かない。Sink を書く人はフィールドを見て振り分けるので、
    /// 1 つだけ pub だと「残りは match しろ」なのか「まだ書いていない」のか読めない。全部の case に 1 つずつ置く。
    ///
    pub def valueAsStr(value: Value): Option[String] = match value {
        case Value.Str(s) => Some(s)
        case _            => None
    }

    ///
    /// 整数なら取り出す。
    ///
    pub def valueAsInt(value: Value): Option[Int64] = match value {
        case Value.Int(n) => Some(n)
        case _            => None
    }

    ///
    /// 小数なら取り出す。整数は写さない（型が違う事を隠さない）。
    ///
    pub def valueAsFloat(value: Value): Option[Float64] = match value {
        case Value.Float(x) => Some(x)
        case _              => None
    }

    ///
    /// 真偽なら取り出す。
    ///
    pub def valueAsBool(value: Value): Option[Bool] = match value {
        case Value.Bool(b) => Some(b)
        case _             => None
    }

    ///
    /// 一覧なら取り出す。
    ///
    pub def valueAsList(value: Value): Option[List[Value]] = match value {
        case Value.List(items) => Some(items)
        case _                 => None
    }

    ///
    /// オブジェクトなら取り出す。
    ///
    pub def valueAsObj(value: Value): Option[Map[String, Value]] = match value {
        case Value.Obj(fields) => Some(fields)
        case _                 => None
    }

    ///
    /// null か。
    ///
    pub def valueIsNull(value: Value): Bool = match value {
        case Value.Null => true
        case _          => false
    }

    ///
    /// JSON の 1 行にする。
    ///
    pub def valueToJsonString(value: Value): String =
        Util.Json.toCompactString(valueToJson(value))

    ///
    /// Util.Json の Json へ写す。
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
    /// WhyNot: NaN と無限大を 0 に倒さない。計測の値が壊れた事が読んだ人に伝わらなくなる。
    /// JSON に書ける表現が無いので null にする。
    ///
    def floatJson(x: Float64): Json =
        if (Float64.isNan(x) or Float64.isInfinite(x)) JNull
        else BigDecimal.fromString(ToString.toString(x)) |> Option.map(JNumber) |> Option.getWithDefault(JNull)

    ///
    /// 行の重さ。Trace < Debug < Info < Warn < Error < Fatal。
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
    /// 行に付く属性。キーは OTel の semantic conventions の名前（http.request.method など）。
    ///
    /// WhyNot: 自前の enum でなく Value を使うのは、JSON にする所で変換が要らず、ライブラリとして切り出す時に差し替える所が 1 か所で済むため。
    ///
    pub type alias Fields = Map[String, Value]

    ///
    /// ログの 1 行。
    ///
    /// - severity: 重さ
    /// - message: 人が読む短い文
    /// - fields: 属性
    ///
    pub type alias Record = { severity = Severity, message = String, fields = Fields }

    ///
    /// 出力先。Record を受けて書く関数。slog の Handler と同じ役目で、値なのでスレッドを跨げる。
    ///
    pub type alias Sink = Record -> Unit \ IO

    // ---- 呼ぶ側 ----

    ///
    /// 段を指定して 1 行出す。enabled が false なら何もしない。
    ///
    pub def log(severity: Severity, message: String, fields: Fields): Unit \ Logfx =
        if (Logfx.enabled(severity)) Logfx.emit({ severity = severity, message = message, fields = fields }) else ()

    ///
    /// 段を指定して 1 行出す。fields は enabled が true の時だけ組み立てる。
    ///
    /// WhyNot: log(severity, message, fields) で済ませない。fields は呼ぶ側で既に
    /// 出来上がっているので、捨てる行でも Map.insert が全部走る。Go の slog が
    /// Enabled() を別に持つのと同じ理由で、組み立てを thunk の後ろに置く口が要る。
    ///
    pub def logWith(severity: Severity, message: String, build: Unit -> Fields \ ef): Unit \ ef + Logfx =
        if (Logfx.enabled(severity)) Logfx.emit({ severity = severity, message = message, fields = build() }) else ()

    /// Trace の行を出す。fields は最後（パイプで受ける）。
    pub def trace(message: String, fields: Fields): Unit \ Logfx =
        log(Severity.Trace, message, fields)

    /// Debug の行を出す。
    pub def debug(message: String, fields: Fields): Unit \ Logfx =
        log(Severity.Debug, message, fields)

    /// Info の行を出す。
    pub def info(message: String, fields: Fields): Unit \ Logfx =
        log(Severity.Info, message, fields)

    /// Warn の行を出す。
    pub def warn(message: String, fields: Fields): Unit \ Logfx =
        log(Severity.Warn, message, fields)

    /// Error の行を出す。
    pub def error(message: String, fields: Fields): Unit \ Logfx =
        log(Severity.Error, message, fields)

    /// Fatal の行を出す。
    pub def fatal(message: String, fields: Fields): Unit \ Logfx =
        log(Severity.Fatal, message, fields)

    /// Trace の行を出す。fields は出す時だけ組み立てる。
    pub def traceWith(message: String, build: Unit -> Fields \ ef): Unit \ ef + Logfx =
        logWith(Severity.Trace, message, build)

    /// Debug の行を出す。fields は出す時だけ組み立てる。
    pub def debugWith(message: String, build: Unit -> Fields \ ef): Unit \ ef + Logfx =
        logWith(Severity.Debug, message, build)

    /// Info の行を出す。fields は出す時だけ組み立てる。
    pub def infoWith(message: String, build: Unit -> Fields \ ef): Unit \ ef + Logfx =
        logWith(Severity.Info, message, build)

    /// Warn の行を出す。fields は出す時だけ組み立てる。
    pub def warnWith(message: String, build: Unit -> Fields \ ef): Unit \ ef + Logfx =
        logWith(Severity.Warn, message, build)

    /// Error の行を出す。fields は出す時だけ組み立てる。
    pub def errorWith(message: String, build: Unit -> Fields \ ef): Unit \ ef + Logfx =
        logWith(Severity.Error, message, build)

    /// Fatal の行を出す。fields は出す時だけ組み立てる。
    pub def fatalWith(message: String, build: Unit -> Fields \ ef): Unit \ ef + Logfx =
        logWith(Severity.Fatal, message, build)

    ///
    /// Java の例外を exception.type / exception.message / exception.cause / exception.stacktrace に写して fields に足す。
    /// message は 200 字で切り、"Detail:" 以降を落とす。null なら空。
    /// cause は getCause を 3 段まで辿って "型: message" を " <- " で繋いだ物。cause が無ければ付かない。
    /// stacktrace は Flix の frame（クラス名に `Def$` か `Clo$` を含む物）だけを 8 つ、" | " 区切り。
    ///
    /// WhyNot: message を丸ごと出さないのは、PG のエラーが Detail: に行の値（鍵やメールアドレス）を入れるため。
    /// WhyNot: frame を全部出さないのは、dev.flix.runtime や JDK の frame は読んでも場所が分からず、DB が落ちた日に 1 行 3 KB が積もるため。
    /// WhyNot: 一番外の例外だけを見ない。JDBC も HTTP も本当の理由（接続拒否、証明書）を包んで投げるので、
    /// 外側だけだと「SQLException が出た」しか残らず、原因が 1 行も出ない。
    /// WhyNot: cause を無制限に辿らない。3 段あれば本当の理由に届き、循環した cause でも止まる。
    /// WhyNot: 改行で区切らない。toJsonLine が制御文字を落とす（log injection 対策）ので、改行だと frame が全部繋がって 1 語になる。
    ///
    pub def exception(error: Throwable, fields: Fields): Fields \ IO =
        let message: String = error.getMessage();
        let causes = causeChain(error.getCause(), 3);
        fields
            |> Fields.str("exception.type", error.getClass().getName())
            |> Fields.str("exception.message", if (Object.isNull(message)) "" else shortMessage(message))
            |> Fields.opt("exception.cause", if (List.isEmpty(causes)) None else Some(List.join(" <- ", causes)))
            |> Fields.str("exception.stacktrace", flixFrames(error) |> List.join(" | "))

    /// getCause の連鎖を budget 段まで "型: message" にする。null で止まる。
    def causeChain(error: Throwable, budget: Int32): List[String] \ IO =
        if (budget <= 0 or Object.isNull(error)) Nil
        else {
            let message: String = error.getMessage();
            let text = "${error.getClass().getName()}: ${if (Object.isNull(message)) "" else shortMessage(message)}";
            let next: Throwable = error.getCause();
            text :: causeChain(next, budget - 1)
        }

    /// "Detail:" より前を取り、前後の空白を落として 200 字に切る。
    def shortMessage(message: String): String =
        String.splitOn(substr = "Detail:", message) |> List.head |> Option.getWithDefault("") |> String.trim |> String.takeLeft(200)

    /// Flix の frame だけを 8 つ。
    def flixFrames(error: Throwable): List[String] \ IO =
        Array.toList(error.getStackTrace())
            |> List.filter(frame -> {
                let className: String = frame.getClassName();
                String.contains(substr = "Def$", className) or String.contains(substr = "Clo$", className)
            })
            |> List.take(8)
            |> List.map(frame -> frame.toString())

    // ---- span と handler ----

    ///
    /// span: thunk の中の全行に fields を足す。行の fields と入れ子の内側が勝つ。
    /// fields が先なのは `run { … } with Logfx.withFields(fields)` の部分適用で使うため。
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
    /// スレッドの入口。全段を sink に渡す。段で絞るなら runWithMin。
    ///
    pub def runWith(sink: Sink, thunk: Unit -> a \ ef): a \ (ef - Logfx) + IO =
        runWithMin(Severity.Trace, sink, thunk)

    ///
    /// スレッドの入口。min より軽い行は enabled が false になり、sink に届かない（min は残す）。
    ///
    /// WhyNot: sink の例外を呼ぶ側に届けないのは、effect の操作の時点で thunk の frame は巻き戻されていて呼ぶ側の catch を素通りし、
    /// Tx の後始末が飛ぶため。ログの失敗で業務を落とさない。代わりに sink が壊れた事を運用者に伝える口は Sink.fallback。
    ///
    /// WhyNot: 段の判定を Sink.minSeverity だけに任せない。sink まで行ってから捨てると、捨てる行でも fields は組み上がっている。
    /// handler で答えれば logWith / infoWith が組み立てごと飛ばせる。
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
    /// テスト用。行を集めて thunk の結果と一緒に返す（古い順）。
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

    // ---- 1 行 JSON ----

    ///
    /// Record を 1 行 JSON にする。キーの順は time / severity / message が先頭で、残りは名前順。
    /// time は ISO 8601 の UTC で ms 固定（.000Z も出す）。severity は小文字。全フィールドの文字列から制御文字を落とす。
    ///
    /// WhyNot: fields の time / severity / message を捨てるのは、同じキーが 2 度出ると JSON を読む側でどちらが残るか決まらないため。
    /// WhyNot: 制御文字を JSON の escape に任せないのは、改行は割れなくても端末のエスケープシーケンスは通り、偽の行を作れてしまうため（log injection）。
    ///
    pub def toJsonLine(timeMillis: Int64, record: Record): String =
        let head = List#{("time", Value.Str(timeText(timeMillis))), ("severity", Value.Str(severityText(record#severity))), ("message", Value.Str(record#message))};
        let rest = record#fields |> Map.remove("time") |> Map.remove("severity") |> Map.remove("message") |> Map.toList;
        List.append(head, rest)
            |> List.map(match (key, value) -> "${Logfx.valueToJsonString(Value.Str(key))}:${Logfx.valueToJsonString(withoutControlChars(value))}")
            |> List.join(",")
            |> body -> "{${body}}"

    ///
    /// 設定の文字列（CMS_LOG_LEVEL など）から Severity。大文字小文字は問わない。知らない語は None。
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

    /// severity の JSON の値。
    def severityText(severity: Severity): String = match severity {
        case Severity.Trace => "trace"
        case Severity.Debug => "debug"
        case Severity.Info  => "info"
        case Severity.Warn  => "warn"
        case Severity.Error => "error"
        case Severity.Fatal => "fatal"
    }

    /// 文字列の中の制御文字を落とす。一覧とオブジェクトは中まで。
    def withoutControlChars(value: Value): Value = match value {
        case Value.Str(text)    => Value.Str(String.replaceMatches(regex = "\\p{Cntrl}", to = "", text))
        case Value.List(items)  => Value.List(List.map(withoutControlChars, items))
        case Value.Obj(fields)  => Value.Obj(Map.map(withoutControlChars, fields))
        case other              => other
    }

    ///
    /// epoch ms を ISO 8601 の UTC（yyyy-MM-ddTHH:mm:ss.SSSZ）にする。負の値は 1970 年より前。
    ///
    /// WhyNot: java.time に寄せない（5 行で済む所を 40 行書いている）。理由は 2 つ。
    /// 1 つ目は effect で、Java の呼び出しは `\ IO` なので toJsonLine と timeText が IO に染まり、
    /// 行の見た目を純粋な関数として表駆動で確かめられなくなる（Sink だけが IO、という境界が崩れる）。
    /// 2 つ目は出力の固定で、DateTimeFormatter.ISO_INSTANT は ms が 0 の時に ".000" を落とすので、
    /// 桁数の揃わない time が混ざる。ログ基盤が時刻の形で取る以上、ここは揺らせない。
    /// 暦の計算自体は Howard Hinnant の civil_from_days で、境界はうるう日・9999 年・負の時刻を表で押さえてある。
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

    /// 負の方向にも切り捨てる割り算（divisor は正）。
    def floorDiv(dividend: Int64, divisor: Int64): Int64 =
        let quotient = dividend / divisor;
        if (dividend - quotient * divisor < 0i64) quotient - 1i64 else quotient

    /// エポックからの日数を (年, 月, 日) に。グレゴリオ暦。
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

    /// 0 埋めの数字。
    def pad(width: Int32, n: Int64): String = String.padLeft(width, '0', Int64.toString(n))

}

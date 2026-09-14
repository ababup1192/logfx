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
/// ログの effect。emit で 1 行を出す。
///
pub eff Logfx {
    def emit(record: Logfx.Record): Unit
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
        /// 整数
        case Int(Int32)
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
    pub def valueAsStr(value: Value): Option[String] = match value {
        case Value.Str(s) => Some(s)
        case _            => None
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
        case Value.Int(n)      => JNumber(Int32.toBigDecimal(n))
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

    /// Trace の行を出す。fields は最後（パイプで受ける）。
    pub def trace(message: String, fields: Fields): Unit \ Logfx =
        Logfx.emit({ severity = Severity.Trace, message = message, fields = fields })

    /// Debug の行を出す。
    pub def debug(message: String, fields: Fields): Unit \ Logfx =
        Logfx.emit({ severity = Severity.Debug, message = message, fields = fields })

    /// Info の行を出す。
    pub def info(message: String, fields: Fields): Unit \ Logfx =
        Logfx.emit({ severity = Severity.Info, message = message, fields = fields })

    /// Warn の行を出す。
    pub def warn(message: String, fields: Fields): Unit \ Logfx =
        Logfx.emit({ severity = Severity.Warn, message = message, fields = fields })

    /// Error の行を出す。
    pub def error(message: String, fields: Fields): Unit \ Logfx =
        Logfx.emit({ severity = Severity.Error, message = message, fields = fields })

    /// Fatal の行を出す。
    pub def fatal(message: String, fields: Fields): Unit \ Logfx =
        Logfx.emit({ severity = Severity.Fatal, message = message, fields = fields })

    ///
    /// Java の例外を exception.type / exception.message / exception.stacktrace の 3 つに写して fields に足す。
    /// message は 200 字で切り、"Detail:" 以降を落とす。null なら空。
    /// stacktrace は Flix の frame（クラス名に `Def$` か `Clo$` を含む物）だけを 8 つ、改行区切り。
    ///
    /// WhyNot: message を丸ごと出さないのは、PG のエラーが Detail: に行の値（鍵やメールアドレス）を入れるため。
    /// WhyNot: frame を全部出さないのは、dev.flix.runtime や JDK の frame は読んでも場所が分からず、DB が落ちた日に 1 行 3 KB が積もるため。
    ///
    pub def exception(error: Throwable, fields: Fields): Fields \ IO =
        let message: String = error.getMessage();
        fields
            |> Fields.str("exception.type", error.getClass().getName())
            |> Fields.str("exception.message", if (Object.isNull(message)) "" else shortMessage(message))
            |> Fields.str("exception.stacktrace", flixFrames(error) |> List.join("\n"))

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
        }

    ///
    /// スレッドの入口。行を sink に渡す。sink が投げた例外はここで受けて捨てる。
    ///
    /// WhyNot: sink の例外を呼ぶ側に届けないのは、effect の操作の時点で thunk の frame は巻き戻されていて呼ぶ側の catch を素通りし、
    /// Tx の後始末が飛ぶため。ログの失敗で業務を落とさない。
    ///
    pub def runWith(sink: Sink, thunk: Unit -> a \ ef): a \ (ef - Logfx) + IO =
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

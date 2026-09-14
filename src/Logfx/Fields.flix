///
/// Fields のビルダー。型付きの追加をパイプで繋ぐ（`Fields.empty() |> Fields.str("k", "v") |> Logfx.info("m")`）。
///
mod Logfx.Fields {

    /// 空。
    pub def empty(): Logfx.Fields = Map.empty()

    /// 文字列を足す。同じ key は後勝ち。
    pub def str(key: String, value: String, fields: Logfx.Fields): Logfx.Fields =
        Map.insert(key, Logfx.Value.Str(value), fields)

    ///
    /// 整数を足す。Int64 のまま入る。
    ///
    /// WhyNot: Logfx.Value.Float に写さないのは、JsonValue が Float を BigDecimal 経由で書くので 12 が 12.0 になり、ログ基盤が小数の型で取るため。
    /// WhyNot: Int32 に丸めない。バイト数や μs の累計は 2 GB を越えるので、丸めると 2147483647 が静かに出続け、
    /// 読む人は値が壊れた事に気づけない。
    ///
    pub def int(key: String, value: Int64, fields: Logfx.Fields): Logfx.Fields =
        Map.insert(key, Logfx.Value.Int(value), fields)

    ///
    /// 小数を足す。NaN と無限大は JSON では null になる（値が壊れた事を残す）。
    ///
    pub def float(key: String, value: Float64, fields: Logfx.Fields): Logfx.Fields =
        Map.insert(key, Logfx.Value.Float(value), fields)

    ///
    /// 入れ子のオブジェクトを足す（Fields をそのまま 1 つの値にする）。
    ///
    pub def obj(key: String, value: Logfx.Fields, fields: Logfx.Fields): Logfx.Fields =
        Map.insert(key, Logfx.Value.Obj(value), fields)

    ///
    /// 任意の Logfx.Value を足す。null（Logfx.Value.Null）や入れ子の一覧はこれで書く。
    ///
    /// WhyNot: case ごとに def を増やさない。Logfx.Fields は Map[String, Logfx.Value] の別名なので、
    /// 覆い切れていないと利用側が Map.insert を直に書き、それが作法として真似される。口を 1 つ開けて塞ぐ。
    ///
    pub def value(key: String, value: Logfx.Value, fields: Logfx.Fields): Logfx.Fields =
        Map.insert(key, value, fields)

    /// 真偽を足す。
    pub def bool(key: String, value: Bool, fields: Logfx.Fields): Logfx.Fields =
        Map.insert(key, Logfx.Value.Bool(value), fields)

    /// 文字列の一覧を足す（graphql.error_codes など）。
    pub def strs(key: String, values: List[String], fields: Logfx.Fields): Logfx.Fields =
        Map.insert(key, Logfx.Value.List(List.map(Logfx.Value.Str, values)), fields)

    /// あれば文字列を足す。None なら付けない。
    pub def opt(key: String, value: Option[String], fields: Logfx.Fields): Logfx.Fields =
        match value {
            case Some(text) => str(key, text, fields)
            case None       => fields
        }

    /// 2 つを合わせる。同じ key は other が勝つ。
    pub def merge(other: Logfx.Fields, fields: Logfx.Fields): Logfx.Fields =
        Map.union(other, fields)

}

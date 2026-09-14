///
/// The field builder. Typed additions chained with a pipe
/// (`Fields.empty() |> Fields.str("k", "v") |> Logfx.info("m")`).
///
mod Logfx.Fields {

    /// The empty fields.
    pub def empty(): Logfx.Fields = Map.empty()

    /// Adds a string. The last write to a key wins.
    pub def str(key: String, value: String, fields: Logfx.Fields): Logfx.Fields =
        Map.insert(key, Logfx.Value.Str(value), fields)

    ///
    /// Adds an integer. It stays an `Int64`. Pass an `Int32` through `Int32.toInt64`.
    ///
    /// WhyNot: not converted to `Logfx.Value.Float`, because a float is written through `BigDecimal`,
    /// so `12` would come out as `12.0` and the log backend would type the field as a float.
    /// WhyNot: not clamped to `Int32`. Byte counts and accumulated microseconds pass 2 GB, so clamping
    /// prints a quiet 2147483647 forever and the reader never learns the value broke.
    ///
    pub def int(key: String, value: Int64, fields: Logfx.Fields): Logfx.Fields =
        Map.insert(key, Logfx.Value.Int(value), fields)

    ///
    /// Adds a float. `NaN` and the infinities become null in JSON, which keeps the breakage visible.
    ///
    pub def float(key: String, value: Float64, fields: Logfx.Fields): Logfx.Fields =
        Map.insert(key, Logfx.Value.Float(value), fields)

    ///
    /// Adds a nested object: a `Fields` used as a single value.
    ///
    pub def obj(key: String, value: Logfx.Fields, fields: Logfx.Fields): Logfx.Fields =
        Map.insert(key, Logfx.Value.Obj(value), fields)

    ///
    /// Adds any `Logfx.Value`. Write null (`Logfx.Value.Null`) and nested lists through this.
    ///
    /// WhyNot: not one `def` per case. `Logfx.Fields` is an alias for `Map[String, Logfx.Value]`,
    /// so anything left uncovered gets written as a bare `Map.insert` at the call site, and that
    /// spreads as the house style. One opening, deliberately left open.
    ///
    pub def value(key: String, value: Logfx.Value, fields: Logfx.Fields): Logfx.Fields =
        Map.insert(key, value, fields)

    /// Adds a boolean.
    pub def bool(key: String, value: Bool, fields: Logfx.Fields): Logfx.Fields =
        Map.insert(key, Logfx.Value.Bool(value), fields)

    /// Adds a list of strings (`graphql.error_codes`, and so on).
    pub def strs(key: String, values: List[String], fields: Logfx.Fields): Logfx.Fields =
        Map.insert(key, Logfx.Value.List(List.map(Logfx.Value.Str, values)), fields)

    /// Adds a string when there is one. `None` adds nothing.
    pub def opt(key: String, value: Option[String], fields: Logfx.Fields): Logfx.Fields =
        match value {
            case Some(text) => str(key, text, fields)
            case None       => fields
        }

    /// Merges two. On a shared key `other` wins.
    pub def merge(other: Logfx.Fields, fields: Logfx.Fields): Logfx.Fields =
        Map.union(other, fields)

}

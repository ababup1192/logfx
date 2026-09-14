#!/usr/bin/env bash
#
# まっさらなプロジェクトから logfx を取り込んで動かす。
#
#   ci/consume.sh local     手元でビルドした .fpkg を lib/ に置いて取り込む（毎回）
#   ci/consume.sh release   GitHub の release から取り込む（tag を打った後）
#
# WhyNot: 手で 1 度試して終わりにしない。0.1.0 を出した時、security = "unrestricted" が
# 要る事も Sink.silent が experimental フラグ無しでは通らない事も、手で試して初めて
# 分かった。自動でなければ、取り込めない版を出す事故は必ず起きる。
#
set -euo pipefail

mode="${1:-local}"
root="$(cd "$(dirname "$0")/.." && pwd)"
version="$(sed -n 's/^version *= *"\(.*\)"/\1/p' "$root/flix.toml")"
flix_version="$(sed -n 's/^flix *= *"\(.*\)"/\1/p' "$root/flix.toml")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/src"
cp "$root/ci/consumer/src/Main.flix" "$work/src/Main.flix"
sed -e "s/@VERSION@/$version/" -e "s/@FLIX@/$flix_version/" "$root/ci/consumer/flix.toml.in" > "$work/flix.toml"

if [ "$mode" = "local" ]; then
    # release を待たずに、今のソースから作った .fpkg を Flix が置く場所に先回りで置く。
    make -C "$root" pkg > /dev/null
    dir="$work/lib/github/ababup1192/logfx/$version"
    mkdir -p "$dir"
    cp "$root/build/logfx/artifact/logfx.fpkg" "$dir/logfx-$version.fpkg"
    cp "$root/flix.toml" "$dir/logfx-$version.toml"
fi

echo "consume($mode): logfx $version / flix $flix_version"
out="$work/out.txt"
# WhyNot: tr -d '\r' にしない。コンパイラの進捗表示が \r で行頭に戻るので、消すと
# 進捗とプログラムの 1 行目が繋がって、行として取り出せなくなる。
(cd "$work" && "$root/bin/flix" run) | tr '\r' '\n' | grep '^{' > "$out" || true

expected_head='{"time":"2025-09-08T02:53:20.123Z","severity":"info","message":"request finished","cache.hit":true,"duration.ratio":0.5,"graphql.error_codes":["NONE"],"http.request.method":"GET","http.response.body.size":3000000000,"http.response.status_code":200,"trace.id":null,"user":{"id":"u1"}}'

fail() { echo "consume($mode): $1" >&2; echo "--- 出た行 ---" >&2; cat "$out" >&2; exit 1; }

[ "$(sed -n 1p "$out")" = "$expected_head" ] || fail "1 行目が期待と違う"
grep -q '"request.id":"r1"' "$out" || fail "withFields の fields が付いていない"
grep -q '"exception.cause":"java.lang.ArithmeticException: / by zero"' "$out" || fail "exception が cause を辿っていない"
grep -q '"logfx.fallback_reason":"java.lang.RuntimeException: sink is down"' "$out" || fail "fallback が理由を付けていない"
grep -q '"message":"primary is down"' "$out" || fail "fallback が行を secondary に渡していない"
! grep -q '"built"' "$out" || fail "落ちるはずの段の fields が組み立てられている"
[ "$(grep -c '^{' "$out")" = "3" ] || fail "行数が 3 でない"

echo "consume($mode): OK（3 行）"

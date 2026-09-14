#!/usr/bin/env bash
#
# Consume logfx from a brand-new project and run it.
#
#   ci/consume.sh local     put the locally built .fpkg in lib/ and consume it (every time)
#   ci/consume.sh release   consume it from the GitHub release (after tagging)
#
# WhyNot: not a one-off manual try. Failures that only show up on the consuming side (the security
# setting, experimental flags, a file left out of the package) are invisible to make check and
# make test, so without automation we are certain to ship a version that cannot be consumed.
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
    # Without waiting for a release, put the .fpkg built from the current source where Flix would place it.
    make -C "$root" pkg > /dev/null
    dir="$work/lib/github/ababup1192/logfx/$version"
    mkdir -p "$dir"
    cp "$root/build/logfx/artifact/logfx.fpkg" "$dir/logfx-$version.fpkg"
    cp "$root/flix.toml" "$dir/logfx-$version.toml"
fi

echo "consume($mode): logfx $version / flix $flix_version"
out="$work/out.txt"
# WhyNot: not tr -d '\r'. The compiler's progress display returns to the start of the line with \r,
# so deleting it joins the progress output with the program's first line and the line can no longer
# be picked out.
(cd "$work" && "$root/bin/flix" run) | tr '\r' '\n' | grep '^{' > "$out" || true

expected_head='{"time":"2025-09-08T02:53:20.123Z","severity":"info","message":"request finished","cache.hit":true,"duration.ratio":0.5,"graphql.error_codes":["NONE"],"http.request.method":"GET","http.response.body.size":3000000000,"http.response.status_code":200,"trace.id":null,"user":{"id":"u1"}}'

fail() { echo "consume($mode): $1" >&2; echo "--- emitted lines ---" >&2; cat "$out" >&2; exit 1; }

[ "$(sed -n 1p "$out")" = "$expected_head" ] || fail "first line differs from the expectation"
grep -q '"request.id":"r1"' "$out" || fail "the withFields fields are not attached"
grep -q '"exception.cause":"java.lang.ArithmeticException: / by zero"' "$out" || fail "exception did not follow the cause"
grep -q '"logfx.fallback_reason":"java.lang.RuntimeException: sink is down"' "$out" || fail "fallback did not attach the reason"
grep -q '"message":"primary is down"' "$out" || fail "fallback did not pass the line to secondary"
! grep -q '"built"' "$out" || fail "the fields of a severity that should be dropped were built"
[ "$(grep -c '^{' "$out")" = "3" ] || fail "the line count is not 3"

echo "consume($mode): OK (3 lines)"

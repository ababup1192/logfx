#!/usr/bin/env bash
#
# What one logfx line costs. Builds bench/ against the .fpkg made from the current source, runs it,
# and compares the result with docs/bench/baseline.json.
#
#   ci/bench.sh          run and compare
#   ci/bench.sh --save   run and write the result as the new baseline
#
# WhyNot: not part of CI. A shared runner's timings move by more than the changes worth catching,
# so a threshold there would either be so loose it catches nothing or so tight it is red by
# accident. This is a thing you run on one machine and compare against itself.
#
# WhyNot: the baseline is not a pass/fail gate even here. It prints every case and only stops on a
# regression past 2x, which is the size of "something structural changed", not noise.
#
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="$(sed -n 's/^version *= *"\(.*\)"/\1/p' "$root/flix.toml")"
baseline="$root/docs/bench/baseline.json"
save=""
[ "${1:-}" = "--save" ] && save="1"

declared="$(sed -n 's/.*"github:ababup1192\/logfx" *= *{ *version *= *"\([^"]*\)".*/\1/p' "$root/bench/flix.toml")"
if [ "$declared" != "$version" ]; then
    echo "bench: it declares logfx $declared, but the current source is $version." >&2
    echo "When the version goes up, bump bench/flix.toml too." >&2
    exit 1
fi

make -C "$root" pkg > /dev/null

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp -R "$root/bench"/. "$work/"
rm -rf "$work/build" "$work/lib"

dir="$work/lib/github/ababup1192/logfx/$version"
mkdir -p "$dir"
cp "$root/build/logfx/artifact/logfx.fpkg" "$dir/logfx-$version.fpkg"
cp "$root/flix.toml" "$dir/logfx-$version.toml"

echo "bench: logfx $version — this takes a minute or two"
out="$work/out.jsonl"
# WhyNot: not tr -d '\r'. The compiler's progress display returns to the start of the line with \r,
# so deleting it joins the progress output with the program's first line.
(cd "$work" && "$root/bin/flix" run) | tr '\r' '\n' | grep '^{"case"' > "$out"

if [ -n "$save" ]; then
    mkdir -p "$(dirname "$baseline")"
    {
        echo "{"
        echo "  \"recorded\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
        echo "  \"logfx\": \"$version\","
        echo "  \"machine\": \"$(uname -s) $(uname -m)\","
        echo "  \"cases\": ["
        sed 's/^/    /' "$out" | sed '$ !s/$/,/'
        echo "  ]"
        echo "}"
    } > "$baseline"
    echo "bench: wrote $baseline"
fi

python3 - "$out" "$baseline" <<'PY'
import json, sys, os

result = [json.loads(line) for line in open(sys.argv[1], encoding="utf-8")]
base = {}
if os.path.exists(sys.argv[2]):
    doc = json.load(open(sys.argv[2], encoding="utf-8"))
    base = {c["case"]: c for c in doc["cases"]}
    print(f"baseline: {doc['logfx']} on {doc['machine']}, recorded {doc['recorded']}")
else:
    print("baseline: none yet (run ci/bench.sh --save to record one)")

width = max(len(r["case"]) for r in result)
print()
print(f"{'case'.ljust(width)}  median   fastest   vs baseline")
worst = 1.0
for row in result:
    name, med, fast = row["case"], row["ns_median"], row["ns_fastest"]
    if name in base:
        was = base[name]["ns_median"]
        ratio = med / was if was else 1.0
        worst = max(worst, ratio)
        delta = f"{(ratio - 1) * 100:+.0f}%  (was {was} ns)"
    else:
        delta = "new"
    print(f"{name.ljust(width)}  {med:>5} ns  {fast:>5} ns   {delta}")
print()
for row in result:
    print(f"  {row['case']}: {row['what']}")

if worst >= 2.0:
    print(f"\nbench: a case is {worst:.1f}x its baseline. Something structural changed.", file=sys.stderr)
    sys.exit(1)
PY

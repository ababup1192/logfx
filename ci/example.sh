#!/usr/bin/env bash
#
# Build and run examples/ against the .fpkg built from the current source.
# Each example checks the emitted lines with its own verify.sh (the argument is the output file).
#
# WhyNot: examples are not left as code snippets in the README. Nobody compiles the code in the
# README, so it is the first thing to rot when the version goes up. A rotten example is worse than
# no example.
#
# WhyNot: the dependency in examples/*/flix.toml is not a "local path". A Flix dependency can only
# be written as github:, and escaping to a path would mean verifying something different from what
# a user actually writes. The actually published version stays written, and the current .fpkg is
# placed into lib/ ahead of time (the same trick as consume.sh).
#
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="$(sed -n 's/^version *= *"\(.*\)"/\1/p' "$root/flix.toml")"

make -C "$root" pkg > /dev/null

for project in "$root"/examples/*/; do
    name="$(basename "$project")"
    declared="$(sed -n 's/.*"github:ababup1192\/logfx" *= *{ *version *= *"\([^"]*\)".*/\1/p' "$project/flix.toml")"
    if [ "$declared" != "$version" ]; then
        echo "example($name): it declares logfx $declared, but the current source is $version." >&2
        echo "When the version goes up, bump examples/$name/flix.toml too (otherwise the example keeps pointing at the API of an old version)." >&2
        exit 1
    fi

    work="$(mktemp -d)"
    cp -R "$project"/. "$work/"
    rm -rf "$work/build" "$work/lib"

    dir="$work/lib/github/ababup1192/logfx/$version"
    mkdir -p "$dir"
    cp "$root/build/logfx/artifact/logfx.fpkg" "$dir/logfx-$version.fpkg"
    cp "$root/flix.toml" "$dir/logfx-$version.toml"

    echo "example($name): logfx $version"
    if [ -d "$work/test" ]; then
        (cd "$work" && "$root/bin/flix" test)
    fi

    out="$work/out.txt"
    # WhyNot: not tr -d '\r'. The compiler's progress display returns to the start of the line with
    # \r, so deleting it joins the progress output with the program's first line and the line can no
    # longer be picked out.
    (cd "$work" && "$root/bin/flix" run) | tr '\r' '\n' | grep '^{' > "$out" || true

    if ! "$project/verify.sh" "$out"; then
        echo "example($name): the emitted lines differ from the expectation" >&2
        cat "$out" >&2
        rm -rf "$work"
        exit 1
    fi
    echo "example($name): OK ($(grep -c '^{' "$out") lines)"
    rm -rf "$work"
done

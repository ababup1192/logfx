#!/usr/bin/env bash
#
# examples/ を、今のソースから作った .fpkg に対してビルドして走らせる。
# 各 example は自分の verify.sh で出た行を見る（引数は出力のファイル）。
#
# WhyNot: examples を README の中のコード片で済ませない。README のコードは誰も
# コンパイルしないので、版を上げた時に真っ先に腐る。腐った例は無い例より悪い。
#
# WhyNot: examples/*/flix.toml の依存を「手元のパス」にしない。Flix の依存は github: しか
# 書けず、パスに逃がすと、利用者が実際に書く物と違う物を確かめる事になる。実際に公開されて
# いる版を書いたまま、lib/ に今の .fpkg を先回りで置く（consume.sh と同じ手）。
#
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="$(sed -n 's/^version *= *"\(.*\)"/\1/p' "$root/flix.toml")"

make -C "$root" pkg > /dev/null

for project in "$root"/examples/*/; do
    name="$(basename "$project")"
    declared="$(sed -n 's/.*"github:ababup1192\/logfx" *= *{ *version *= *"\([^"]*\)".*/\1/p' "$project/flix.toml")"
    if [ "$declared" != "$version" ]; then
        echo "example($name): logfx $declared を書いているが、今のソースは $version。" >&2
        echo "版を上げたら examples/$name/flix.toml も上げる（例が古い版の API を指したままになる）。" >&2
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
    # WhyNot: tr -d '\r' にしない。コンパイラの進捗表示が \r で行頭に戻るので、消すと
    # 進捗とプログラムの 1 行目が繋がって、行として取り出せなくなる。
    (cd "$work" && "$root/bin/flix" run) | tr '\r' '\n' | grep '^{' > "$out" || true

    if ! "$project/verify.sh" "$out"; then
        echo "example($name): 出た行が期待と違う" >&2
        cat "$out" >&2
        rm -rf "$work"
        exit 1
    fi
    echo "example($name): OK（$(grep -c '^{' "$out") 行）"
    rm -rf "$work"
done

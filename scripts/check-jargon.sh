#!/usr/bin/env bash
# 日本語で書く所に、言い換え先のある和語・比喩が残っていないか見張る。
#
# WhyNot: 語の一覧をこのスクリプトに書かない。scripts/jargon-denylist.txt から毎回読む
# （手で持った一覧は、語を足した人が書き忘れた時に素通りになる）。
#
# WhyNot: レビューだけに置かない。同じ語は直した後にも入り込む（この表を持ってきた
# nextcms では、機械の見張りを入れるまで何度も戻った）。
#
# WhyNot: コードの文字列リテラルと識別子は見ない。logfx が外に出す文字列は全部英語なので、
# 日本語が残っているとすれば人が読む文の方。
set -euo pipefail

cd "$(dirname "$0")/.."
denylist="scripts/jargon-denylist.txt"

# 日本語で書く所だけ。src / test / examples / ci / bin は英語なので見ない。
targets=(README.md AGENTS.md)
while IFS= read -r doc; do targets+=("$doc"); done < <(find docs -name '*.md' 2>/dev/null | sort)

found=0
while IFS=$'\t' read -r word replacement exclude; do
    case "$word" in ''|'#'*) continue;; esac
    for target in "${targets[@]}"; do
        [ -f "$target" ] || continue
        hits="$(grep -nE "$word" "$target" || true)"
        if [ -n "$exclude" ]; then
            hits="$(printf '%s\n' "$hits" | grep -vE "$exclude" || true)"
        fi
        [ -n "$hits" ] || continue
        printf '%s\n' "$hits" | while IFS= read -r hit; do
            echo "${target}:${hit%%:*}: 「${word}」は使いません → ${replacement}"
        done
        found=1
    done
done < "$denylist"

if [ "$found" = "1" ]; then
    echo "" >&2
    echo "言い換えは ${denylist} にあります。" >&2
    exit 1
fi
echo "check-jargon: OK（${#targets[@]} ファイル）"

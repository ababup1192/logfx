#!/usr/bin/env bash
# 出た行（$1）が、この例で見せたい物になっているか。
set -euo pipefail
out="$1"

# enrich は全行に付く。
grep -q '"service.name":"example-server"' "$out"
# キーの順は time / severity / message が先頭。
grep -q '^{"time":"[0-9-]*T[0-9:.]*Z","severity":' "$out"
# span は行に付く。
grep -q '"request.id":"r3"' "$out"
# 落ちた経路は exception の写しが付く。
grep -q '"exception.type":"java.lang.RuntimeException"' "$out"
grep -q '"exception.message":"connection refused"' "$out"
# 既定は Info なので debug の行は出ない。
! grep -q '"message":"routing"' "$out"
# /health は Info の行を出さない。出るのは /posts と /nope の 2 行。
[ "$(grep -c '^{' "$out")" = "2" ]

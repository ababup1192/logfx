#!/usr/bin/env bash
# 出た行（$1）が README に載せている JSON と同じ形か。
set -euo pipefail
out="$1"

[ "$(grep -c '^{' "$out")" = "1" ]
grep -q '"severity":"info","message":"request finished"' "$out"
grep -q '"http.request.method":"GET","http.response.status_code":200,"url.path":"/posts"}$' "$out"

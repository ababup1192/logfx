#!/usr/bin/env bash
# Checks that the line that came out ($1) has the shape the README shows.
set -euo pipefail
out="$1"

[ "$(grep -c '^{' "$out")" = "1" ]
grep -q '"severity":"info","message":"request finished"' "$out"
grep -q '"http.request.method":"GET","http.response.status_code":200,"url.path":"/posts"}$' "$out"

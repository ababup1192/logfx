#!/usr/bin/env bash
# Checks that the lines that came out ($1) show what this example is here to show.
set -euo pipefail
out="$1"

# enrich reaches every line.
grep -q '"service.name":"example-server"' "$out"
# time / severity / message come first.
grep -q '^{"time":"[0-9-]*T[0-9:.]*Z","severity":' "$out"
# The span is on the line.
grep -q '"request.id":"r3"' "$out"
# The failing route carries the exception fields.
grep -q '"exception.type":"java.lang.RuntimeException"' "$out"
grep -q '"exception.message":"connection refused"' "$out"
# A frame is written file:line, with no absolute path.
grep -q '"exception.stacktrace":"Handler\.[^"]*(Handler\.flix:[0-9]*)' "$out"
! grep -q '"exception.stacktrace":"[^"]*(/' "$out"
# Info is the default, so the debug line stays out.
! grep -q '"message":"routing"' "$out"
# /health emits nothing at Info. What comes out is /posts and /nope.
[ "$(grep -c '^{' "$out")" = "2" ]

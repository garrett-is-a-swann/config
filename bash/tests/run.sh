#!/usr/bin/env bash
# Run every *.test.sh in this directory; exit non-zero if any fail.
set -u
cd "$(dirname "${BASH_SOURCE[0]}")"

status=0
for t in ./*.test.sh; do
    echo "# $t"
    bash "$t" || status=1
done
exit "$status"

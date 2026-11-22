#!/usr/bin/env bash
# Scores the sample submission with our binary on the decrypted puzzles; result leaves the runner encrypted.
set -euo pipefail
CHUNK="$1"; PZ="$RUNNER_TEMP/pz"
mkdir -p work out
chmod +x bin/*
{
  echo "chunk: $CHUNK  date: $(date -u +%FT%TZ)  nproc: $(nproc)"
  bin/elfcheck score "$PZ/puzzles.csv" "$PZ/sample_submission.csv" --strict
} > work/check.txt 2>&1 || true
tar -czf work/result.tar.gz -C work check.txt
openssl cms -encrypt -binary -aes256 -in work/result.tar.gz -outform DER -out out/result.cms keys/st26_cert.pem
rm -rf work
echo "check: done"

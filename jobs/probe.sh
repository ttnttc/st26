#!/usr/bin/env bash
# Probe job. Everything it measures goes into work/ and leaves the runner only encrypted (out/result.cms).
# The public log shows step names only.
set -euo pipefail
CASES="${1:-200000}"
mkdir -p work out
{  # diagnostics only: never let a missing tool or an empty grep stop the job
  set +e
  echo "date: $(date -u +%FT%TZ)"
  echo "nproc: $(nproc)"
  free -m
  lscpu | grep -E 'Model name|^CPU\(s\)|Thread|Flags' | sed 's/Flags:.*/&/' | cut -c1-400
  grep -o -w -E 'avx2|avx512f|bmi2' /proc/cpuinfo | sort | uniq -c
  df -h . | tail -1
  set -e
} > work/hardware.txt 2>&1
chmod +x bin/*
bin/test_core > work/test_core.txt 2>&1 && echo "unit tests: ok" || echo "unit tests: FAILED"
python3 -I jobs/synth.py work "$CASES" > work/synth.txt
start=$(date +%s.%N)
bin/elfcheck lines work/puzzles.csv work/cells.tsv > work/verdicts.tsv
end=$(date +%s.%N)
python3 -I - "$start" "$end" "$CASES" > work/timing.txt <<'PY'
import sys
s, e, n = float(sys.argv[1]), float(sys.argv[2]), int(sys.argv[3])
print(f"elfcheck lines: {n} cells in {e - s:.2f} s ({n / (e - s):.0f} cells/s)")
PY
cut -f2 work/verdicts.tsv | sort | uniq -c > work/verdict_counts.txt
tar -czf work/result.tar.gz -C work hardware.txt test_core.txt synth.txt timing.txt verdict_counts.txt
openssl cms -encrypt -binary -aes256 -in work/result.tar.gz -outform DER -out out/result.cms keys/st26_cert.pem
rm -rf work
echo "probe: done"

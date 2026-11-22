#!/usr/bin/env bash
# One generation chunk: decrypt inputs and config, run 4 workers of bin/elfgen on this chunk's puzzles,
# encrypt everything that leaves the runner. The public log shows step names and a done line only.
set -euo pipefail
: "${ST26_DATA_KEY:?missing}"
PZ="$RUNNER_TEMP/pz"
mkdir -p "$PZ" work out
openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -pass env:ST26_DATA_KEY -in data/puzzles.enc | tar -xzf - -C "$PZ"
PARAMS=$(echo "$CONFIGS" | base64 -d | openssl enc -d -aes-256-cbc -pbkdf2 -iter 10000 -pass env:ST26_DATA_KEY \
         | python3 -I -c "import json,sys; print(json.load(sys.stdin)['$CFG'])")
python3 -I jobs/select_ids.py "$PZ/split.json" "$SPLIT" "$CHUNK" "$OF" 4 work/ids
chmod +x bin/*
PFILE="$PZ/puzzles.csv"
[ "$SPLIT" = "practice" ] && PFILE="$PZ/practice_puzzles.csv"
for w in 0 1 2 3; do
  TR=""
  case " $PARAMS " in *" c_mode=2 "*) TR="trace=work/trace_$w.jsonl" ;; esac
  ( ulimit -v 3500000; bin/elfgen "$PFILE" "work/ids_$w.txt" $PARAMS $TR > "work/out_$w.tsv" 2> "work/stat_$w.tsv" ) &
done
wait
echo "nproc $(nproc) cfg $CFG chunk $CHUNK/$OF" > work/meta.txt
tar -czf work/result.tar.gz -C work meta.txt $(cd work && ls out_*.tsv stat_*.tsv trace_*.jsonl 2>/dev/null)
openssl cms -encrypt -binary -aes256 -in work/result.tar.gz -outform DER -out out/result.cms keys/st26_cert.pem
rm -rf work "$PZ"
echo "gen: done"
